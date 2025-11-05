#!/usr/bin/env python3
"""
UltraWhisper v3 Backend Server
WebSocket server for real-time transcription using whisper.cpp with Metal GPU acceleration
"""

import asyncio
import json
import logging
import os
import sys
import signal
import argparse
from pathlib import Path
from typing import Dict, Optional, Any
import websockets
import numpy as np
from whisper_wrapper import WhisperModel

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class TranscriptionSession:
    """Manages a single transcription session with audio buffering"""

    def __init__(self, session_id: str, config: dict):
        self.session_id = session_id
        self.config = config
        self.audio_buffer = []
        self.is_active = False
        self.sample_rate = 16000  # Target sample rate

    def add_audio_chunk(self, audio_data: bytes):
        """Add audio chunk to buffer"""
        # Convert bytes to numpy array (PCM 16-bit little-endian)
        audio_array = np.frombuffer(audio_data, dtype=np.int16)
        self.audio_buffer.extend(audio_array)

    def get_audio_array(self) -> np.ndarray:
        """Get complete audio as numpy array"""
        return np.array(self.audio_buffer, dtype=np.int16)

    def clear_buffer(self):
        """Clear audio buffer"""
        self.audio_buffer.clear()


class WhisperCppBackend:
    """Main backend service for whisper.cpp transcription"""

    def __init__(self):
        self.sessions: Dict[str, TranscriptionSession] = {}

        # Model path
        backend_dir = Path(__file__).parent
        self.model_path = backend_dir / "whisper.cpp" / "models" / "ggml-large-v3-turbo.bin"

        if not self.model_path.exists():
            raise FileNotFoundError(f"Model not found at {self.model_path}")

        logger.info(f"Loading whisper model: {self.model_path}")
        logger.info("This will take a few seconds on first load...")

        # Load model once and keep in memory
        self.model = WhisperModel(str(self.model_path), use_gpu=True)

        logger.info(f"Model loaded successfully with Metal GPU acceleration!")
        logger.info("Ready for fast transcriptions!")

    def create_session(self, session_id: str, config: dict) -> TranscriptionSession:
        """Create a new transcription session"""
        session = TranscriptionSession(session_id, config)
        self.sessions[session_id] = session
        logger.info(f"Created session: {session_id}")
        return session

    def get_session(self, session_id: str) -> Optional[TranscriptionSession]:
        """Get existing session"""
        return self.sessions.get(session_id)

    def remove_session(self, session_id: str):
        """Remove a session"""
        if session_id in self.sessions:
            del self.sessions[session_id]
            logger.info(f"Removed session: {session_id}")

    def transcribe_session(self, session_id: str) -> dict:
        """Transcribe audio from a session using whisper.cpp"""
        session = self.get_session(session_id)
        if not session:
            raise ValueError(f"Session {session_id} not found")

        try:
            audio_array = session.get_audio_array()

            if len(audio_array) < 1600:  # Less than 0.1 seconds
                return {
                    'session_id': session_id,
                    'text': '',
                    'segments': [],
                    'language': 'en',
                    'avg_logprob': 0.0
                }

            logger.info(f"Transcribing {len(audio_array)/16000:.2f}s of audio for session {session_id}")

            # Get language from session config, default to 'auto' for auto-detection
            # Handle None/null values by using 'auto'
            language = session.config.get('language') or 'auto'

            # Convert 'auto' to None for whisper.cpp (None means auto-detect)
            whisper_language = None if language == 'auto' else language
            logger.info(f"Using language: {language} (whisper param: {whisper_language})")

            # Use the in-memory model - MUCH faster!
            result = self.model.transcribe(
                audio_array,
                language=whisper_language,
                n_threads=4
            )

            full_text = result['text']
            segments = result['segments']
            language = result['language']

            logger.info(f"Transcription complete: '{full_text}' (language: {language})")

            return {
                'session_id': session_id,
                'text': full_text,
                'segments': segments,
                'language': language,
                'avg_logprob': 0.0
            }

        except Exception as e:
            logger.error(f"Transcription failed for session {session_id}: {e}")
            raise


class WebSocketServer:
    """WebSocket server handler"""

    def __init__(self, backend: WhisperCppBackend):
        self.backend = backend

    async def handle_client(self, websocket, path):
        """Handle WebSocket client connection"""
        client_addr = websocket.remote_address
        logger.info(f"Client connected: {client_addr}")

        try:
            async for message in websocket:
                if isinstance(message, bytes):
                    # Binary message - audio chunk
                    await self.handle_audio_chunk(websocket, message)
                else:
                    # Text message - JSON command
                    await self.handle_json_message(websocket, message)

        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Client disconnected: {client_addr}")
        except Exception as e:
            logger.error(f"Error handling client {client_addr}: {e}")

    async def handle_json_message(self, websocket, message_str: str):
        """Handle JSON messages from client"""
        try:
            message = json.loads(message_str)
            message_type = message.get('type')
            message_id = message.get('id')
            data = message.get('data', {})

            logger.debug(f"Received message: {message_type}")

            if message_type == 'hello':
                await self.handle_hello(websocket, message_id, data)
            elif message_type == 'start_session':
                await self.handle_start_session(websocket, message_id, data)
            elif message_type == 'end_session':
                await self.handle_end_session(websocket, message_id, data)
            elif message_type == 'cancel':
                await self.handle_cancel(websocket, message_id, data)
            else:
                await self.send_error(websocket, message_id, 'UNSUPPORTED_MESSAGE', f'Unknown message type: {message_type}')

        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON received: {e}")
            await self.send_error(websocket, None, 'INVALID_JSON', str(e))
        except Exception as e:
            logger.error(f"Error handling JSON message: {e}")
            await self.send_error(websocket, None, 'INTERNAL', str(e))

    async def handle_audio_chunk(self, websocket, audio_data: bytes):
        """Handle audio chunk data"""
        logger.debug(f"Received {len(audio_data)} bytes of audio data")

        if not hasattr(websocket, 'current_session_id'):
            logger.warning("No current session ID on websocket - audio chunk ignored")
            return

        session_id = websocket.current_session_id
        session = self.backend.get_session(session_id)

        if not session:
            logger.error(f"Session {session_id} not found for audio chunk")
            return

        if not session.is_active:
            logger.warning(f"Session {session_id} is not active - audio chunk ignored")
            return

        session.add_audio_chunk(audio_data)
        total_audio_duration = len(session.audio_buffer) / session.sample_rate
        logger.debug(f"Added {len(audio_data)} bytes to session {session_id}, total: {total_audio_duration:.2f}s")

    async def handle_hello(self, websocket, message_id: str, data: dict):
        """Handle hello message"""
        logger.info(f"Hello from client - app_version: {data.get('app_version')}, locale: {data.get('locale')}")

        response = {
            'type': 'hello_ack',
            'id': message_id,
            'data': {
                'serverVersion': '0.3.0',
                'backend': 'whisper.cpp',
                'gpu': 'Metal',
                'models': ['large-v3-turbo', 'large-v3']
            }
        }

        await websocket.send(json.dumps(response))

    async def handle_start_session(self, websocket, message_id: str, data: dict):
        """Handle start_session command"""
        session_id = data.get('sessionId')

        if not session_id:
            await self.send_error(websocket, message_id, 'BAD_REQUEST', 'sessionId is required')
            return

        # Create new session
        session = self.backend.create_session(session_id, data)
        session.is_active = True

        logger.info(f"Started transcription session: {session_id}")

        # Store current session in websocket context for audio chunks
        websocket.current_session_id = session_id

        # Send acknowledgment
        response = {
            'type': 'session_started',
            'id': message_id,
            'data': {
                'sessionId': session_id,
                'status': 'ready'
            }
        }
        await websocket.send(json.dumps(response))
        logger.info(f"Session {session_id} started and ready for audio")

    async def handle_end_session(self, websocket, message_id: str, data: dict):
        """Handle end_session command"""
        session_id = data.get('sessionId')

        if not session_id:
            await self.send_error(websocket, message_id, 'BAD_REQUEST', 'sessionId is required')
            return

        try:
            # Transcribe the session (runs synchronously, but in executor)
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(None, self.backend.transcribe_session, session_id)

            # Send final result
            response = {
                'type': 'final',
                'data': result
            }
            await websocket.send(json.dumps(response))

            # Clean up session
            self.backend.remove_session(session_id)
            if hasattr(websocket, 'current_session_id'):
                delattr(websocket, 'current_session_id')

        except Exception as e:
            logger.error(f"Error ending session {session_id}: {e}")
            await self.send_error(websocket, message_id, 'INTERNAL', str(e))

    async def handle_cancel(self, websocket, message_id: str, data: dict):
        """Handle cancel command"""
        session_id = data.get('sessionId')

        if session_id:
            self.backend.remove_session(session_id)

        if hasattr(websocket, 'current_session_id'):
            delattr(websocket, 'current_session_id')

        logger.info(f"Cancelled session: {session_id}")

    async def send_error(self, websocket, message_id: Optional[str], code: str, message: str, session_id: Optional[str] = None):
        """Send error message to client"""
        response = {
            'type': 'error',
            'id': message_id,
            'data': {
                'sessionId': session_id,
                'code': code,
                'message': message
            }
        }
        await websocket.send(json.dumps(response))


async def main():
    """Main server entry point"""
    parser = argparse.ArgumentParser(description='UltraWhisper v3 Backend Server (whisper.cpp + Metal)')
    parser.add_argument('--port', type=int, default=0, help='Port to listen on (0 for random)')
    parser.add_argument('--host', default='127.0.0.1', help='Host to bind to')
    parser.add_argument('--debug', action='store_true', help='Enable debug logging')

    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    # Initialize backend
    backend = WhisperCppBackend()
    logger.info("Backend initialized successfully")

    # Create WebSocket server
    server_handler = WebSocketServer(backend)

    # Start server
    try:
        # Use the correct handler method for websockets library
        async def websocket_handler(websocket):
            path = getattr(websocket, 'path', '/ws')
            await server_handler.handle_client(websocket, path)

        server = await websockets.serve(
            websocket_handler,
            args.host,
            args.port
        )

        # Get the actual port
        actual_port = server.sockets[0].getsockname()[1]

        # Print port for Flutter app to read
        print(f"SERVER_PORT:{actual_port}")
        sys.stdout.flush()

        logger.info(f"WebSocket server started on {args.host}:{actual_port}")
        logger.info(f"Using Metal GPU acceleration on Apple M3 Max")

        # Set up signal handlers
        def signal_handler(signum, frame):
            logger.info("Shutting down server...")
            server.close()

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        # Wait for server to close
        await server.wait_closed()

    except Exception as e:
        logger.error(f"Server error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    asyncio.run(main())
