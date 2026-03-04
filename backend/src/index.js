require('dotenv').config();
const express = require('express');
const http = require('http');
const cookieParser = require('cookie-parser');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const userRoutes = require('./routes/user.routes');

const { connectDB } = require('./config/db');

const authRoutes = require('./routes/auth.routes');
const contentRoutes = require('./routes/content.routes');
const moodRoutes = require('./routes/mood.routes');
const psychologyRoutes = require('./routes/psychology.routes');
const chatRoutes = require('./routes/chat.routes');
const { registerChatSocket } = require('./socket/chat.socket');


const app = express();
const server = http.createServer(app);

app.use(express.json({ limit: '250mb' }));
app.use('/uploads', express.static('uploads'));
app.use(cookieParser());
app.use(cors({
  origin: (process.env.CLIENT_ORIGIN || 'http://10.202.14.73:5173').split(','),
  credentials: true
}));
app.use(helmet());
app.use(morgan('dev'));

app.get('/health', (req, res) => res.json({ ok: true, uptime: process.uptime() }));

app.use('/auth', authRoutes);
app.use('/content', contentRoutes);
app.use('/mood', moodRoutes);
app.use('/user', userRoutes);
app.use('/psychology', psychologyRoutes);
app.use('/chat', chatRoutes);

const allowedOrigins = (process.env.CLIENT_ORIGIN || 'http://10.202.14.73:5173')
  .split(',')
  .map((v) => v.trim())
  .filter(Boolean);

let io = null;
try {
  const { Server } = require('socket.io');
  io = new Server(server, {
    cors: {
      origin: allowedOrigins,
      credentials: true,
    },
  });
  registerChatSocket(io);
  console.log('✅ Socket.IO enabled');
} catch (err) {
  console.warn('⚠️ Socket.IO is not installed, running without realtime chat');
}

app.set('io', io);

const PORT = process.env.PORT || 4000;
connectDB(process.env.MONGODB_URI)
  .then(() => server.listen(PORT, () => console.log(`🚀 Server listening on port ${PORT}`)))
  .catch(err => {
    console.error('❌ Mongo connect error:', err.message);
    process.exit(1);
  });
