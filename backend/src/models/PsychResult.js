const mongoose = require('mongoose');

const psychResultSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    score: { type: Number, required: true },
    maxScore: { type: Number, required: true },
    stateText: { type: String, required: true },
    answers: [
      {
        questionId: { type: String, required: true }, 
        value: { type: Number, required: true },      
      },
    ],
  },
  { timestamps: true }
);

module.exports = mongoose.model('PsychResult', psychResultSchema);
