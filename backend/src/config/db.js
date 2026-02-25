const mongoose = require('mongoose');

async function connectDB(uri) {
  mongoose.set('strictQuery', true);

  const candidates = [
    uri,
    process.env.MONGODB_URI_FALLBACK,
    process.env.MONGODB_URI_LOCAL,
  ].filter(Boolean);

  if (!candidates.length) {
    throw new Error('MONGODB_URI is not set');
  }

  let lastError;

  for (const candidate of candidates) {
    try {
      await mongoose.connect(candidate, {
        dbName: process.env.MONGODB_DB_NAME || 'qorga',
        serverSelectionTimeoutMS: 8000,
      });
      console.log(`MongoDB connected (${candidate.startsWith('mongodb+srv://') ? 'srv' : 'direct'})`);
      return;
    } catch (error) {
      lastError = error;
      const looksLikeSrvDnsIssue =
        candidate.startsWith('mongodb+srv://') &&
        /querySrv|ENOTFOUND|ECONNREFUSED/i.test(error.message || '');

      if (looksLikeSrvDnsIssue) {
        console.error('MongoDB SRV DNS lookup failed. Trying fallback URI if configured...');
      }
    }
  }

  throw lastError;
}

module.exports = { connectDB };
