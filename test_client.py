import asyncio
import numpy as np
import cv2
import websockets

async def main():
    # Create a dummy image and encode as JPEG
    img = np.zeros((480, 640, 3), dtype=np.uint8)
    cv2.putText(img, 'TEST', (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 4, (255,255,255), 5)
    _, buf = cv2.imencode('.jpg', img)
    data = buf.tobytes()

    uri = 'ws://localhost:8000/ws'
    async with websockets.connect(uri) as ws:
        await ws.send(data)
        resp = await ws.recv()
        print('Server response:', resp)

if __name__ == '__main__':
    asyncio.run(main())
