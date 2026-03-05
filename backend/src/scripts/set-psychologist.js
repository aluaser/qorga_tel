#!/usr/bin/env node
const path = require('path');
const bcrypt = require('bcrypt');
const dotenv = require('dotenv');
const mongoose = require('mongoose');
const User = require('../models/user');
const { connectDB } = require('../config/db');

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

async function run() {
  const emailArg = process.argv[2];
  const passwordArg = process.argv[3];
  const displayNameArg = process.argv[4];

  const email = normalizeEmail(emailArg || process.env.DEFAULT_PSYCHOLOGIST_EMAIL);
  const password = String(passwordArg || '').trim();
  const displayName = String(displayNameArg || 'Psychologist').trim();

  if (!email) {
    console.error(
      'Usage: node src/scripts/set-psychologist.js <email> <password> [displayName]'
    );
    process.exitCode = 1;
    return;
  }

  if (!password || password.length < 6) {
    console.error('Password is required and must be at least 6 characters.');
    process.exitCode = 1;
    return;
  }

  await connectDB(process.env.MONGODB_URI);

  const passwordHash = await bcrypt.hash(password, 10);

  const user = await User.findOneAndUpdate(
    { email },
    {
      $set: {
        email,
        role: 'psychologist',
        displayName,
        passwordHash,
        password: '',
      },
    },
    {
      upsert: true,
      new: true,
      setDefaultsOnInsert: true,
    }
  ).lean();

  console.log(
    JSON.stringify(
      {
        ok: true,
        id: String(user._id),
        email: user.email,
        role: user.role,
      },
      null,
      2
    )
  );
}

run()
  .catch((err) => {
    console.error('Failed to set psychologist:', err.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect().catch(() => {});
  });
