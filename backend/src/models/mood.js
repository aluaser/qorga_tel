const mongoose = require('mongoose');

const moodSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    date: {
      type: Date,
      required: true,
    },
    mood: {
      type: String,
      enum: ['very_happy', 'happy', 'neutral', 'sad', 'angry'],
      required: true,
    },
    note: {
      type: String,
      default: '',
    },
  },
  { timestamps: true }
);

moodSchema.index({ userId: 1, date: 1 }, { unique: true });

module.exports = mongoose.model('Mood', moodSchema);
