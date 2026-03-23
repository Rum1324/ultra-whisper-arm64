#!/usr/bin/env python3
"""
Test script to verify the backend is working
"""

import asyncio
import websockets
import json
import numpy as np
import sys

async def test_transcription():
    uri = "ws://127.0.0.1:8082"

    try:
        async with websockets.connect(uri) as websocket:
            print(f"✅ Connected to WebSocket server at {uri}")

            # Send hello
            hello_msg = json.dumps({
                "type": "hello",
                "id": "test-1",
                "data": {
                    "appVersion": "test",
                    "locale": "en-US"
                }
            })
            await websocket.send(hello_msg)
            print("📤 Sent hello message")

            # Get hello_ack
            response = await websocket.recv()
            response_data = json.loads(response)
            print(f"📥 Received: {response_data['type']}")

            # Start session
            start_msg = json.dumps({
                "type": "start_session",
                "id": "test-2",
                "data": {
                    "sessionId": "test-session-1",
                    "language": "auto",
                    "model": "large-v3-turbo",
                    "device": "metal",
                    "computeType": "default",
                    "enablePartial": False,
                    "post": {
                        "smartCaps": True,
                        "punctuation": True,
                        "disfluencyCleanup": True
                    }
                }
            })
            await websocket.send(start_msg)
            print("📤 Sent start_session")

            # Get session_started ack
            response = await websocket.recv()
            response_data = json.loads(response)
            print(f"📥 Received: {response_data['type']}")

            # Send some test audio (5 seconds of silence at 16kHz)
            print("📤 Sending test audio (5 seconds of silence)...")
            sample_rate = 16000
            duration = 5  # seconds

            # Create silence audio
            audio_data = np.zeros(sample_rate * duration, dtype=np.int16)

            # Add a small beep in the middle to test if it processes
            beep_freq = 440  # A4 note
            beep_duration = 0.5  # seconds
            beep_samples = int(sample_rate * beep_duration)
            beep_start = int(sample_rate * 2)  # Start at 2 seconds

            t = np.linspace(0, beep_duration, beep_samples)
            beep = np.sin(2 * np.pi * beep_freq * t) * 0.3 * 32767
            audio_data[beep_start:beep_start + beep_samples] = beep.astype(np.int16)

            # Send audio in chunks
            chunk_size = 1600  # 100ms chunks at 16kHz
            for i in range(0, len(audio_data), chunk_size):
                chunk = audio_data[i:i+chunk_size]
                await websocket.send(chunk.tobytes())
                await asyncio.sleep(0.01)  # Small delay between chunks

            print("✅ Audio sent")

            # End session to get transcription
            end_msg = json.dumps({
                "type": "end_session",
                "id": "test-3",
                "data": {
                    "sessionId": "test-session-1"
                }
            })
            await websocket.send(end_msg)
            print("📤 Sent end_session")

            # Get final transcription
            response = await websocket.recv()
            response_data = json.loads(response)
            print(f"📥 Received: {response_data['type']}")

            if response_data['type'] == 'final':
                print("\n✅ TRANSCRIPTION RESULT:")
                print(f"   Text: '{response_data['data'].get('text', '')}'")
                print(f"   Language: {response_data['data'].get('language', 'unknown')}")
            else:
                print(f"\n❌ Unexpected response: {response_data}")

    except Exception as e:
        print(f"\n❌ Error: {e}")
        return False

    return True

if __name__ == "__main__":
    print("🧪 Testing UltraWhisper Backend...")
    print("-" * 40)

    success = asyncio.run(test_transcription())

    if success:
        print("\n✅ Backend test completed successfully!")
    else:
        print("\n❌ Backend test failed!")
        sys.exit(1)
