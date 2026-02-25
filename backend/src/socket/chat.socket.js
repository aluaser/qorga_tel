function _safeString(value) {
  if (value == null) return null;
  return String(value);
}

function mapSocketMessage(msg) {
  return {
    id: _safeString(msg._id),
    chatId: _safeString(msg.chatId),
    chatType: _safeString(msg.chatType),
    senderType: _safeString(msg.senderType),
    recipientType: _safeString(msg.recipientType),
    senderId: _safeString(msg.senderId),
    recipientId: _safeString(msg.recipientId),
    text: _safeString(msg.text) || '',
    createdAt: msg.createdAt,
    read: Boolean(msg.read),
  };
}

function emitChatMessage(io, msg) {
  if (!io || !msg) return;

  const payload = mapSocketMessage(msg);

  if (payload.chatId) {
    io.to(`chat:${payload.chatId}`).emit('message:new', payload);
  }

  if (payload.senderId) {
    io.to(`user:${payload.senderId}`).emit('chat:updated', {
      chatId: payload.chatId,
      messageId: payload.id,
      at: payload.createdAt,
    });
  }

  if (payload.recipientId) {
    io.to(`user:${payload.recipientId}`).emit('chat:updated', {
      chatId: payload.chatId,
      messageId: payload.id,
      at: payload.createdAt,
    });
  }
}

function registerChatSocket(io) {
  io.on('connection', (socket) => {
    const userId = _safeString(socket.handshake.query?.userId || '').trim();

    if (userId) {
      socket.join(`user:${userId}`);
    }

    socket.on('join_chat', (payload = {}) => {
      const chatId = _safeString(payload.chatId || '').trim();
      if (!chatId) return;
      socket.join(`chat:${chatId}`);
    });

    socket.on('leave_chat', (payload = {}) => {
      const chatId = _safeString(payload.chatId || '').trim();
      if (!chatId) return;
      socket.leave(`chat:${chatId}`);
    });
  });
}

module.exports = {
  emitChatMessage,
  registerChatSocket,
};
