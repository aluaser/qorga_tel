const mongoose = require('mongoose');

const userSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      lowercase: true,
    },

    passwordHash: {
      type: String,
      default: '',
    },

    password: {
      type: String,
      default: '',
    },

    displayName: {
      type: String,
      default: '',
      trim: true,
    },

    role: {
      type: String,
      default: 'user',
    },

    resetCode: {
      type: String,
    },
    resetCodeExpires: {
      type: Date,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model('User', userSchema);
