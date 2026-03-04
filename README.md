# qorga_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Deploy backend to Render

This repo includes [render.yaml](render.yaml) for the Node backend in `backend/`.

### Required Render env vars

- `MONGODB_URI`
- `JWT_ACCESS_SECRET`
- `CLIENT_ORIGIN` (comma-separated, include any web frontends you use)
- `PUBLIC_BASE_URL` (set to your Render URL, e.g. `https://qorga-backend.onrender.com`)

Optional vars are listed in [backend/.env.example](backend/.env.example).

### iPhone run command (Flutter app -> Render backend)

```bash
flutter run -d <IPHONE_DEVICE_ID> \
  --dart-define=API_BASE_URL=https://<your-render-service>.onrender.com \
  --dart-define=WS_BASE_URL=wss://<your-render-service>.onrender.com
```
