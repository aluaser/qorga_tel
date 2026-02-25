const mongoose = require('mongoose');

const chatMessageSchema = new mongoose.Schema(
  {
    chatId: {
      type: String,
      required: true,
      trim: true,
      index: true,
    },
    chatType: {
      type: String,
      enum: ['human', 'ai'],
      default: 'human',
      index: true,
    },
    senderType: {
      type: String,
      enum: ['user', 'ai'],
      default: 'user',
    },
    recipientType: {
      type: String,
      enum: ['user', 'ai'],
      default: 'user',
    },
    senderId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    recipientId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    text: {
      type: String,
      required: true,
      trim: true,
      maxlength: 1000,
    },
    read: {
      type: Boolean,
      default: false,
    },
  },
  { timestamps: true }
);

chatMessageSchema.index({ chatId: 1, createdAt: 1 });
chatMessageSchema.index({ senderId: 1, recipientId: 1, createdAt: -1 });
chatMessageSchema.index({ recipientId: 1, read: 1, createdAt: -1 });

module.exports = mongoose.model('ChatMessage', chatMessageSchema);
