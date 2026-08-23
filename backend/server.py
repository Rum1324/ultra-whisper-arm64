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
import threading
from pathlib import Path
from typing import Dict, Optional, Any
import websockets
import numpy as np
from whisper_wrapper import WhisperModel
from postprocess import apply_post_processing
from meeting import (
    MIN_WINDOW_SAMPLES,
    TRACK_SPEAKERS,
    VAD_PEAK_RMS_THRESHOLD,
    MeetingSession,
    PendingWindow,
    build_window,
    peak_window_rms,
    split_audio_frame,
)
from summarize.contracts import TranscriptWindow, Unavailable
from summarize.llm import DEFAULT_HOST as OLLAMA_DEFAULT_HOST
from summarize.pipeline import summarize_meeting


def ollama_host() -> str:
    """
    Where to reach Ollama.

    Overridable because summarization is the one part of this app that is not
    self-contained (see CLAUDE.md): the user may already run Ollama somewhere
    other than the default port, and the tests point it at a stub.
    """
    return os.environ.get('ULTRAWHISPER_OLLAMA_HOST') or OLLAMA_DEFAULT_HOST

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
        self.meetings: Dict[str, MeetingSession] = {}

        # One whisper context, shared by dictation and by every meeting window.
        # whisper_full() is not reentrant against a single context, and meeting
        # windows now transcribe on a worker thread while the user may still be
        # dictating. This only serializes those calls — no dictation result
        # changes, which the protocol requires.
        self._model_lock = threading.Lock()

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

    def create_meeting(self, meeting_id: str, data: dict) -> MeetingSession:
        """Create a meeting session from a `start_meeting` payload."""
        meeting = MeetingSession(
            meeting_id,
            meeting_type=data.get('meetingType') or 'generic',
            language=data.get('language'),
            title=data.get('title'),
            window_seconds=int(data.get('windowSeconds') or 120),
        )
        self.meetings[meeting_id] = meeting
        logger.info(
            f"Created meeting: {meeting_id} (type={meeting.meeting_type}, "
            f"window={meeting.window_seconds}s)"
        )
        return meeting

    def get_meeting(self, meeting_id: str) -> Optional[MeetingSession]:
        return self.meetings.get(meeting_id)

    def remove_meeting(self, meeting_id: str):
        if meeting_id in self.meetings:
            del self.meetings[meeting_id]
            logger.info(f"Removed meeting: {meeting_id}")

    def transcribe_window(self, meeting: MeetingSession, pending: PendingWindow) -> TranscriptWindow:
        """
        Transcribe one rolling window, one track at a time.

        Runs on a worker thread via `run_in_executor`, the pattern
        `handle_end_session` already uses, so the WebSocket loop stays
        responsive while a window is in whisper.

        Each track is transcribed independently and the results merged by time
        in `build_window`; that merge is where speaker attribution comes from.
        No custom-vocabulary prompt is passed — the dictation path gates that to
        English, and a meeting is exactly the case where the wrong language
        costs the most.
        """
        language = meeting.language or None
        per_track: Dict[int, list] = {}

        for track, audio in pending.tracks.items():
            if len(audio) < MIN_WINDOW_SAMPLES:
                continue

            # Per-window VAD. One side of a conversation is silent for minutes
            # at a time, and a window of pure silence yielding no segments is
            # correct rather than a failure.
            peak_rms = peak_window_rms(audio)
            if peak_rms < VAD_PEAK_RMS_THRESHOLD:
                logger.debug(
                    f"meeting {meeting.meeting_id} window {pending.index} "
                    f"track {TRACK_SPEAKERS.get(track, track)}: silent (peak RMS={peak_rms:.4f})"
                )
                continue

            try:
                with self._model_lock:
                    result = self.model.transcribe(audio, language=language, n_threads=4)
                per_track[track] = result.get('segments') or []
            except Exception as e:
                # One track failing costs that track's share of one window. The
                # meeting keeps running; losing an hour of transcript to a
                # single bad window would be far worse.
                logger.error(
                    f"meeting {meeting.meeting_id} window {pending.index} "
                    f"track {track} failed: {e}"
                )

        return build_window(pending.index, pending.t0, pending.t1, per_track)

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

            # Energy-based VAD: reject clips with no speech-level energy anywhere.
            #
            # We measure the LOUDEST 30ms window, not the whole-clip average.
            # In toggle mode a clip is padded with silence before you start
            # speaking and after you stop; averaging over that silence drags a
            # real (but short or quiet) utterance below the threshold and drops
            # it entirely. The window peak is silence-invariant, so this only
            # ever keeps MORE audio than the old whole-clip average — a clip
            # that passed before still passes (peak >= mean), while quiet/short
            # utterances that were wrongly dropped now get transcribed.
            audio_float = audio_array.astype(np.float32) / 32768.0
            frame = 480  # 30ms @ 16kHz
            n_frames = len(audio_float) // frame
            if n_frames > 0:
                frames = audio_float[:n_frames * frame].reshape(n_frames, frame)
                peak_rms = float(np.sqrt(np.mean(frames ** 2, axis=1)).max())
            else:
                peak_rms = float(np.sqrt(np.mean(audio_float ** 2)))
            if peak_rms < 0.01:
                logger.info(f"🔇 No speech-level energy (peak 30ms RMS={peak_rms:.4f}) — skipping to prevent hallucination")
                return {
                    'session_id': session_id,
                    'text': '',
                    'segments': [],
                    'language': 'en',
                    'avg_logprob': 0.0
                }

            logger.info(f"Transcribing {len(audio_array)/16000:.2f}s of audio for session {session_id} (peak 30ms RMS={peak_rms:.4f})")

            # Get language from session config, default to 'auto' for auto-detection
            # Handle None/null values by using 'auto'
            language = session.config.get('language') or 'auto'
            logger.info(f"🌐 Session config language: {session.config.get('language')} → Using: '{language}'")

            # Convert 'auto' to None for whisper.cpp (None means auto-detect)
            whisper_language = None if language == 'auto' else language
            logger.info(f"📤 Passing to whisper: language='{whisper_language}' (None = auto-detect)")

            # Post-processing options and custom dictionary terms from the client
            post = session.config.get('post') or {}
            custom_terms = post.get('customTerms') or []
            initial_prompt = ', '.join(custom_terms) if custom_terms else None
            if initial_prompt:
                logger.info(f"📖 Using custom dictionary terms: {custom_terms}")

            # Use the in-memory model - MUCH faster!
            result = self.model.transcribe(
                audio_array,
                language=whisper_language,
                n_threads=4,
                initial_prompt=initial_prompt
            )

            full_text = apply_post_processing(
                result['text'],
                smart_caps=post.get('smartCaps', True),
                punctuation=post.get('punctuation', True),
                disfluency_cleanup=post.get('disfluencyCleanup', True),
            )
            segments = result['segments']
            detected_language = result['language']

            logger.info(f"✅ Transcription complete:")
            logger.info(f"   🔍 Detected language: {detected_language}")
            logger.info(f"   📝 Text: '{full_text[:100]}{'...' if len(full_text) > 100 else ''}'")

            return {
                'session_id': session_id,
                'text': full_text,
                'segments': segments,
                'language': detected_language,
                'avg_logprob': 0.0
            }

        except Exception as e:
            logger.error(f"Transcription failed for session {session_id}: {e}")
            raise


class WebSocketServer:
    """WebSocket server handler"""

    def __init__(self, backend: WhisperCppBackend):
        self.backend = backend
        # One drain task per meeting. Windows must reach the client in order,
        # and a second drain racing the first would interleave them.
        self._drains: Dict[str, asyncio.Lock] = {}

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
            elif message_type == 'start_meeting':
                await self.handle_start_meeting(websocket, message_id, data)
            elif message_type == 'end_meeting':
                await self.handle_end_meeting(websocket, message_id, data)
            elif message_type == 'summarize':
                await self.handle_summarize(websocket, message_id, data)
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

        # A meeting on this connection means meeting framing: one leading track
        # byte, then PCM. Dictation frames stay bare PCM. The session kind is
        # what tells the two apart, so they never collide.
        meeting_id = getattr(websocket, 'current_meeting_id', None)
        if meeting_id is not None:
            await self.handle_meeting_audio(websocket, meeting_id, audio_data)
            return

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
        """
        Handle cancel command.

        Extended for meetings: given a meetingId this drops the meeting and its
        retained transcript. `end_meeting` deliberately does not — summarize
        still needs it — so cancel is the only thing that frees a transcript.
        """
        meeting_id = data.get('meetingId')
        if meeting_id:
            self.backend.remove_meeting(meeting_id)
            self._drains.pop(meeting_id, None)
            if getattr(websocket, 'current_meeting_id', None) == meeting_id:
                delattr(websocket, 'current_meeting_id')
            logger.info(f"Cancelled meeting: {meeting_id}")
            return

        session_id = data.get('sessionId')

        if session_id:
            self.backend.remove_session(session_id)

        if hasattr(websocket, 'current_session_id'):
            delattr(websocket, 'current_session_id')

        logger.info(f"Cancelled session: {session_id}")

    # ------------------------------------------------------------------
    # Meetings
    # ------------------------------------------------------------------

    async def handle_start_meeting(self, websocket, message_id: str, data: dict):
        """Handle start_meeting command"""
        meeting_id = data.get('meetingId')
        if not meeting_id:
            await self.send_error(websocket, message_id, 'BAD_REQUEST', 'meetingId is required')
            return

        meeting = self.backend.create_meeting(meeting_id, data)
        websocket.current_meeting_id = meeting_id
        self._drains[meeting_id] = asyncio.Lock()

        await self._send(websocket, {
            'type': 'meeting_started',
            'id': message_id,
            'data': {
                'meetingId': meeting_id,
                'meetingType': meeting.meeting_type,
                'windowSeconds': meeting.window_seconds,
                'status': 'ready',
            },
        })

    async def handle_meeting_audio(self, websocket, meeting_id: str, payload: bytes):
        """Buffer one track-tagged meeting frame and drain any full window."""
        meeting = self.backend.get_meeting(meeting_id)
        if not meeting or not meeting.is_active:
            return

        try:
            track, pcm = split_audio_frame(payload)
        except ValueError as e:
            # Malformed framing is a genuine fault: accepting it would put
            # shifted noise into the transcript under the wrong speaker.
            logger.error(f"meeting {meeting_id}: bad audio frame: {e}")
            await self.send_error(websocket, None, 'BAD_FRAME', str(e))
            return

        meeting.add_audio(track, pcm)
        await self.drain_meeting_windows(websocket, meeting)

    async def drain_meeting_windows(self, websocket, meeting: MeetingSession, final: bool = False):
        """
        Transcribe and emit every window that is ready.

        Held under a per-meeting lock so windows reach the client in order. The
        lock is not awaited when already held: the next audio frame is moments
        away and will drain whatever this pass leaves behind, whereas queueing
        a drain per frame would pile up thousands of them over a meeting.
        """
        lock = self._drains.get(meeting.meeting_id)
        if lock is None:
            return
        if lock.locked() and not final:
            return

        async with lock:
            loop = asyncio.get_event_loop()
            while True:
                pending = meeting.pop_ready_window()
                if pending is None:
                    if not final:
                        break
                    pending = meeting.flush()
                    if pending is None:
                        break
                    final = False  # the flush yields exactly one window

                window = await loop.run_in_executor(
                    None, self.backend.transcribe_window, meeting, pending
                )
                meeting.record(window)
                await self._send(websocket, {
                    'type': 'transcript_window',
                    'data': {
                        'meetingId': meeting.meeting_id,
                        'index': window.index,
                        't0': window.t0,
                        't1': window.t1,
                        'segments': [
                            {'t0': s.t0, 't1': s.t1, 'speaker': s.speaker, 'text': s.text}
                            for s in window.segments
                        ],
                    },
                })

    async def handle_end_meeting(self, websocket, message_id: str, data: dict):
        """
        Handle end_meeting command.

        Flushes the trailing partial window and keeps the session alive, so
        `summarize` can still run against it. Only `cancel` frees the transcript.
        """
        meeting_id = data.get('meetingId')
        meeting = self.backend.get_meeting(meeting_id) if meeting_id else None
        if not meeting:
            await self.send_error(websocket, message_id, 'NO_SUCH_MEETING',
                                  f'Unknown meetingId: {meeting_id}')
            return

        meeting.is_active = False
        await self.drain_meeting_windows(websocket, meeting, final=True)

        if getattr(websocket, 'current_meeting_id', None) == meeting_id:
            delattr(websocket, 'current_meeting_id')

        await self._send(websocket, {
            'type': 'meeting_ended',
            'id': message_id,
            'data': {
                'meetingId': meeting_id,
                'segments': len(meeting.segments),
            },
        })

    async def handle_summarize(self, websocket, message_id: str, data: dict):
        """
        Handle summarize command.

        Runs classify → map → reduce → render on a worker thread so progress
        events can actually be delivered while it works. Safe to call more than
        once on the same meeting, including with a different model — that is the
        intended way to retry with something bigger after a weak note.
        """
        meeting_id = data.get('meetingId')
        meeting = self.backend.get_meeting(meeting_id) if meeting_id else None
        if not meeting:
            await self.send_error(websocket, message_id, 'NO_SUCH_MEETING',
                                  f'Unknown meetingId: {meeting_id}')
            return

        model = data.get('model')
        if not model:
            await self.send_error(websocket, message_id, 'BAD_REQUEST', 'model is required')
            return

        loop = asyncio.get_event_loop()

        def report(stage: str, completed: int, total: int):
            # Called from the worker thread; hop back onto the loop to send.
            asyncio.run_coroutine_threadsafe(
                self._send(websocket, {
                    'type': 'summary_progress',
                    'data': {
                        'meetingId': meeting_id,
                        'stage': stage,
                        'completed': completed,
                        'total': total,
                    },
                }),
                loop,
            )

        started = loop.time()
        result = await loop.run_in_executor(
            None,
            lambda: summarize_meeting(
                meeting.transcript(),
                model=model,
                meeting_type=data.get('meetingType') or meeting.meeting_type,
                title=meeting.title,
                host=ollama_host(),
                progress=report,
            ),
        )

        # Not an error. Summarization is an enhancement layered on a transcript
        # that already works; Ollama being absent must never read as a failed
        # operation, and must never cost the user their transcript.
        if isinstance(result, Unavailable):
            await self._send(websocket, {
                'type': 'summary_unavailable',
                'id': message_id,
                'data': {
                    'meetingId': meeting_id,
                    'reason': result.reason,
                    'detail': result.detail,
                    'remedy': result.remedy,
                },
            })
            return

        await self._send(websocket, {
            'type': 'summary_final',
            'id': message_id,
            'data': {
                'meetingId': meeting_id,
                'markdown': result.markdown,
                'note': {
                    'title': result.note.title,
                    'meetingType': result.note.meeting_type,
                    'sections': [
                        {
                            'title': section.title,
                            'style': section.style,
                            'items': [
                                {'text': item.text,
                                 'children': [{'text': c.text} for c in item.children]}
                                for item in section.items
                            ],
                        }
                        for section in result.note.sections
                    ],
                },
                'model': result.model,
                'elapsedSeconds': round(loop.time() - started, 1),
            },
        })

    async def _send(self, websocket, payload: dict):
        """Send one JSON event, tolerating a client that has gone away."""
        try:
            await websocket.send(json.dumps(payload))
        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Dropped {payload.get('type')}: client disconnected")

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
