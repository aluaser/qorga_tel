// src/routes/mood.routes.js
const express = require('express');
const mongoose = require('mongoose');
const router = express.Router();
const Mood = require('../models/mood');
const User = require('../models/user');
const UserAlert = require('../models/UserAlert');
const { createSmtpTransport, getSmtpConfig } = require('../config/smtp');

const MOOD_RISK_WINDOW_DAYS = 7;
const MOOD_RISK_BAD_DAYS_THRESHOLD = 5;
const MOOD_RISK_COOLDOWN_HOURS = 24;

const { from: SMTP_FROM } = getSmtpConfig();
const smtpTransport = createSmtpTransport();

async function sendMoodRiskEmail(toEmail) {
  if (!smtpTransport || !toEmail) {
    return { ok: false, error: 'SMTP_NOT_CONFIGURED' };
  }

  const subject = 'Qorga: Қолдау қажет болуы мүмкін';
  const text =
    'Соңғы күндері көңіл-күйіңіз жиі төмен болғаны байқалды. Бұл қорқынышты емес. Психологқа жүгіну - қалыпты және пайдалы қадам.';
  const html = `
    <div style="font-family: Arial, sans-serif; line-height: 1.45;">
      <h2>Qorga қолдауы</h2>
      <p>Соңғы күндері көңіл-күйіңіз жиі төмен болғаны байқалды.</p>
      <p><strong>Бұл қорқынышты емес.</strong> Психологқа жүгіну - қалыпты және пайдалы қадам.</p>
      <p>Өзіңізге қамқор болыңыз. Қажет болса, чат арқылы маманға жазыңыз.</p>
    </div>
  `;

  const result = await smtpTransport.sendMail({
    from: SMTP_FROM,
    to: toEmail,
    subject,
    text,
    html,
  });

  if (!result?.messageId) {
    return { ok: false, error: 'SMTP_MESSAGE_ID_MISSING' };
  }
  return { ok: true };
}

async function maybeCreateMoodRiskAlert(userId) {
  const now = new Date();
  const startDate = new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate() - (MOOD_RISK_WINDOW_DAYS - 1)
  );
  startDate.setHours(0, 0, 0, 0);

  const recent = await Mood.find({
    userId,
    date: { $gte: startDate, $lte: now },
  })
    .sort({ date: -1 })
    .lean();

  const badDaysCount = recent.filter(
    (m) => m.mood === 'sad' || m.mood === 'angry'
  ).length;

  if (badDaysCount < MOOD_RISK_BAD_DAYS_THRESHOLD) {
    return { triggered: false };
  }

  const cooldownSince = new Date(now.getTime() - MOOD_RISK_COOLDOWN_HOURS * 3600 * 1000);
  const existingRecentAlert = await UserAlert.findOne({
    userId,
    type: 'mood_risk',
    createdAt: { $gte: cooldownSince },
  }).lean();

  if (existingRecentAlert) {
    return { triggered: false, reason: 'cooldown' };
  }

  const user = await User.findById(userId, { email: 1 }).lean();
  let emailSent = false;
  let emailError = '';

  try {
    const emailResult = await sendMoodRiskEmail(user?.email || '');
    emailSent = emailResult.ok;
    if (!emailResult.ok) emailError = emailResult.error || 'unknown_email_error';
  } catch (e) {
    emailError = e?.message || String(e);
  }

  await UserAlert.create({
    userId,
    type: 'mood_risk',
    message:
      'Соңғы күндері көңіл-күйіңіз жиі төмен болды. Психологқа жүгіну - қалыпты әрі қауіпсіз қадам.',
    riskWindowDays: MOOD_RISK_WINDOW_DAYS,
    badDaysCount,
    deliveredChannels: {
      inApp: true,
      email: emailSent,
    },
    readAt: null,
  });

  console.log(
    `mood-risk alert created for user=${userId} badDays=${badDaysCount} emailSent=${emailSent}`
  );
  if (!emailSent && emailError) {
    console.error(`email delivery failed for mood-risk user=${userId}:`, emailError);
  }

  return { triggered: true, badDaysCount, emailSent };
}

// ✅ Создание или обновление записи о настроении
router.post('/', async (req, res) => {
  try {
    const { userId, date, mood, note } = req.body;

    if (!userId || !date || !mood) {
      return res.status(400).json({
        ok: false,
        error: 'userId, date и mood обязательны',
      });
    }

    const moodDate = new Date(date);
    moodDate.setHours(0, 0, 0, 0);

    const moodEntry = await Mood.findOneAndUpdate(
      {
        userId,
        date: moodDate,
      },
      {
        userId,
        date: moodDate,
        mood,
        note: note || '',
      },
      {
        upsert: true, // создаёт, если нет
        new: true, // возвращает обновлённый документ
        setDefaultsOnInsert: true,
      }
    );

    // Персональный риск-анализ: 5 плохих дней из последних 7
    await maybeCreateMoodRiskAlert(userId);

    return res.status(200).json({
      ok: true,
      data: moodEntry,
    });
  } catch (error) {
    console.error('Mood save error:', error);
    return res.status(500).json({
      ok: false,
      error: 'Failed to save mood',
    });
  }
});

// ✅ Получение статистики за месяц (по userId)
router.get('/stats', async (req, res) => {
  try {
    const { month, year, userId } = req.query;

    if (!month || !year || !userId) {
      return res.status(400).json({
        ok: false,
        error: 'userId, month и year обязательны',
      });
    }

    const startDate = new Date(year, month - 1, 1);
    const endDate = new Date(year, month, 0, 23, 59, 59);

    const stats = await Mood.aggregate([
      {
        $match: {
          userId: new mongoose.Types.ObjectId(userId),
          date: { $gte: startDate, $lte: endDate },
        },
      },
      {
        $group: {
          _id: '$mood',
          count: { $sum: 1 },
        },
      },
    ]);

    return res.status(200).json(stats);
  } catch (error) {
    console.error('Stats error:', error);
    return res.status(500).json({
      ok: false,
      error: 'Failed to get stats',
    });
  }
});

// ✅ Получение настроения за конкретный день (по userId)
router.get('/day', async (req, res) => {
  try {
    const { userId, date } = req.query;

    if (!userId || !date) {
      return res.status(400).json({
        ok: false,
        error: 'userId и date обязательны',
      });
    }

    const moodDate = new Date(date);
    moodDate.setHours(0, 0, 0, 0);

    const mood = await Mood.findOne({
      userId,
      date: moodDate,
    });

    return res.status(200).json({
      ok: true,
      data: mood,
    });
  } catch (error) {
    console.error('Get mood error:', error);
    return res.status(500).json({
      ok: false,
      error: 'Failed to get mood',
    });
  }
});

module.exports = router;
