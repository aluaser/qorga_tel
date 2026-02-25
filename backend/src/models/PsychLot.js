const mongoose = require('mongoose');

const psychLotSchema = new mongoose.Schema(
  {
    psychologistId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    psychologistName: {
      type: String,
      default: '',
      trim: true,
    },
    title: {
      type: String,
      required: true,
      trim: true,
      maxlength: 200,
    },
    description: {
      type: String,
      default: '',
      trim: true,
      maxlength: 4000,
    },
    videoUrl: {
      type: String,
      required: true,
      trim: true,
    },
    videoOriginalName: {
      type: String,
      default: '',
      trim: true,
    },
  },
  { timestamps: true }
);

psychLotSchema.index({ createdAt: -1 });
psychLotSchema.index({ psychologistId: 1, createdAt: -1 });

module.exports = mongoose.model('PsychLot', psychLotSchema);
