Project: Go AV Streaming Server1. OverviewThe goal of this project is to create a lightweight, secure, and configurable server application in Go that runs on a Linux machine. This server will capture audio and video from local devices (like webcams or microphones), encode them in real-time, and stream them over the network to authorized clients (such as mobile phones or web browsers).The server will act as a general-purpose AV recorder and streamer, allowing clients to remotely access and monitor any AV source configured on the host machine.2. Core FeaturesConfigurable AV Sources: Define a "menu" of available audio and video streams via an external config.json file.Multi-Device Support: Ability to stream from multiple devices simultaneously (e.g., a webcam and a system microphone).Real-time Transcoding: Use ffmpeg as the backend engine to handle the heavy lifting of capturing and encoding AV streams (e.g., to H.264 for video, Opus for audio).WebSocket Streaming: Use WebSockets for low-latency, real-time data transmission.Simple, Robust Auth: Secure the server with a single Pre-Shared Key (PSK) that is generated on startup.Console-Friendly PSK: Display the PSK on the server's console as both plain text and an ASCII QR code for easy scanning by mobile clients.Dynamic Stream Selection: Clients can query the server to get a list of available streams and then request a specific one.One Stream Per-Socket: Each requested AV stream will be served over its own dedicated WebSocket connection.3. Technical Architecture3.1. Go ServerThe core application will be a single Go binary. Its responsibilities are:On Startup:Read and parse the config.json file to load all available Device definitions.Generate a single, cryptographically-secure Pre-Shared Key (PSK).Print the PSK to the console.Generate and print an ASCII QR code of the PSK to the console.Start an HTTP server.Runtime:Handle HTTP requests for device discovery.Handle WebSocket upgrade requests for streaming.Manage ffmpeg subprocesses for each active stream.3.2. ffmpeg SubprocessesThe Go application will not handle raw video/audio data directly. Instead, when a client requests a stream:The server will find the corresponding device config (from config.json).It will spawn an ffmpeg command as a subprocess, using the arguments defined in the config.ffmpeg will be configured to output its encoded stream (e.g., H.264 or Opus) to stdout.The Go server will read this stdout pipe and forward the binary data directly to the client's WebSocket.When the client disconnects, the Go server will terminate the corresponding ffmpeg subprocess.4. Security ModelSecurity is based on a single, auto-generated PSK. This PSK is used for two distinct authentication flows:HTTP Auth (for /devices): The client must include the PSK in the HTTP header:Authorization: Bearer <your_psk_here>WebSocket Auth (for /stream/*): After the WebSocket connection is established, the client's very first message must be a text message containing only the PSK. If the key is valid, the server will begin streaming. If not, the server will close the connection.Note: For production use, the server must be configured to use TLS (https:// and wss://) to ensure all communication, including the PSK, is encrypted over the wire. This project's initial scope can use self-signed certificates for development.5. API Endpoints5.1. GET /devicesDescription: Returns a JSON array of all available AV devices.Authentication: Requires HTTP Bearer Token Auth (see Security Model).Success Response (200 OK):[
  {
    "id": "webcam-high",
    "name": "Logitech C920 (High Res)",
    "type": "video"
  },
  {
    "id": "system-audio",
    "name": "Desktop Audio (PulseAudio Monitor)",
    "type": "audio"
  }
]
Failure Response (401 Unauthorized):Unauthorized5.2. GET /stream/{deviceID}Description: Initiates a WebSocket connection for a specific stream. The {deviceID} must match one of the id fields from the config.json.Protocol: HTTP/1.1 Upgrade (WebSocket)Authentication: Requires WebSocket PSK Auth (see Security Model).Data Flow:Client connects (e.g., ws://server:8080/stream/webcam-high).Client sends one text message: <your_psk_here>.Server validates PSK.Server starts sending a stream of binary WebSocket messages (the raw H.264/Opus frames from ffmpeg).6. Configuration (config.json)The server will be configured via a config.json file. This file defines the ffmpeg commands for each available device.{
  "devices": [
    {
      "id": "webcam-high",
      "name": "Logitech C920 (High Res)",
      "type": "video",
      "ffmpeg_input": "/dev/video0",
      "ffmpeg_args": ["-f", "v4l2", "-framerate", "30", "-video_size", "1920x1080"],
      "output_codec": "libx264",
      "output_args": ["-preset", "ultrafast", "-tune", "zerolatency", "-f", "h264"]
    },
    {
      "id": "system-audio",
      "name": "Desktop Audio (PulseAudio Monitor)",
      "type": "audio",
      "ffmpeg_input": "default",
      "ffmpeg_args": ["-f", "pulse", "-i", "alsa_output.pci-0000_00_1f.3.analog-stereo.monitor"],
      "output_codec": "libopus",
      "output_args": ["-b:a", "128k", "-f", "opus"]
    }
  ]
}
7. Initial TasksSet up the Go project (go.mod) with initial dependencies (nhooyr.io/websocket, skip2/go-qrcode, mdp/qrterminal/v3).Implement the config.json loading logic.Implement the PSK generation and console QR code display.Implement the GET /devices HTTP handler with bearer token authentication.Implement the GET /stream/{deviceID} WebSocket handler with the "first message" PSK authentication.(STRETCH) Implement the real ffmpeg subprocess logic to replace the simulated data stream. This involves:Constructing the exec.CommandContext() from the device config.Reading from the command's StdoutPipe.Writing the data as websocket.MessageBinary to the client.Ensuring the process is cleaned up when the context is done (client disconnects).
