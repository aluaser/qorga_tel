const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const nodemailer = require('nodemailer');
const User = require('../models/user');
const { validatePassword } = require('../utils/password-policy');

const router = express.Router();

const ACCESS_TTL = process.env.ACCESS_TTL || '15m';
const JWT_SECRET = process.env.JWT_ACCESS_SECRET || 'dev-secret';
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SMTP_SERVICE = String(process.env.SMTP_SERVICE || 'gmail').trim();
const SMTP_USER = String(process.env.SMTP_USER || '').trim();
const SMTP_PASS = String(process.env.SMTP_PASS || '').trim();
const SMTP_FROM = String(process.env.SMTP_FROM || SMTP_USER).trim();

const smtpTransport = (SMTP_USER && SMTP_PASS)
  ? nodemailer.createTransport({
      service: SMTP_SERVICE,
      auth: {
        user: SMTP_USER,
        pass: SMTP_PASS,
      },
    })
  : null;

async function sendPasswordResetCodeEmail(toEmail, code) {
  if (!smtpTransport) {
    return { ok: false, error: 'GMAIL_SMTP_NOT_CONFIGURED' };
  }

  const subject = 'Qorga: Құпия сөзді қалпына келтіру коды';
  const text = `Qorga коды: ${code}. Бұл код 10 минутқа жарамды.`;
  const html = `
    <div style="font-family: Arial, sans-serif; line-height: 1.4;">
      <h2 style="margin-bottom: 8px;">Qorga</h2>
      <p>Құпия сөзді қалпына келтіру коды:</p>
      <p style="font-size: 28px; letter-spacing: 4px; font-weight: bold; margin: 12px 0;">${code}</p>
      <p>Код 10 минут ішінде жарамды.</p>
      <p style="color: #666;">Егер бұл сұрауды сіз жасамаған болсаңыз, бұл хатты елемеңіз.</p>
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
    return { ok: false, error: 'GMAIL_MESSAGE_ID_MISSING' };
  }

  return { ok: true };
}

const registerLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 8,
});
const loginLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
});

router.post('/register', registerLimiter, async (req, res) => {
  try {
    const { email, password, displayName } = req.body || {};
    const normalizedEmail = String(email || '').trim().toLowerCase();

    const errors = [];
    if (!normalizedEmail || !EMAIL_REGEX.test(normalizedEmail)) errors.push('Некорректный email');
    const passwordError = validatePassword(password);
    if (passwordError) errors.push(passwordError);
    if (displayName && displayName.length > 40) errors.push('displayName слишком длинный');
    if (errors.length) return res.status(400).json({ ok: false, errors });

    const exists = await User.findOne({ email: normalizedEmail });
    if (exists) {
      return res.status(409).json({ ok: false, error: 'Email уже зарегистрирован' });
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const user = await User.create({
      email: normalizedEmail,
      passwordHash,
      displayName,
      role: 'user',
    });

    const accessToken = jwt.sign(
      { sub: user._id.toString(), type: 'user' },
      JWT_SECRET,
      { expiresIn: ACCESS_TTL }
    );

    return res.status(201).json({
      ok: true,
      data: {
        accessToken,
        user: {
          id: user._id,
          email: user.email,
          displayName: user.displayName,
          role: user.role,
          avatarBase64: user.avatarBase64 || '',
        },
      },
    });
  } catch (e) {
    console.error('Register error:', e);
    return res.status(500).json({ ok: false, error: 'Server error' });
  }
});

router.post('/login', loginLimiter, async (req, res) => {
  try {
    const { email, password } = req.body || {};
    const normalizedEmail = String(email || '').trim().toLowerCase();

    if (!normalizedEmail) {
      return res.status(400).json({ ok: false, error: 'Email required' });
    }

    const user = await User.findOne({ email: normalizedEmail });
    if (!user) {
      return res.status(401).json({ ok: false, error: 'Пайдаланушы табылмады' });
    }

    let passwordOk = false;

    if (user.passwordHash) {
      passwordOk = await bcrypt.compare(password || '', user.passwordHash);
    } else if (user.password) {
      passwordOk = user.password === (password || '');
    }

    if (!passwordOk) {
      return res.status(401).json({ ok: false, error: 'Неверные email или пароль' });
    }

    const token = jwt.sign(
      { sub: user._id.toString(), type: 'user' },
      JWT_SECRET,
      { expiresIn: ACCESS_TTL }
    );

    return res.json({
      ok: true,
      data: {
        accessToken: token,
        user: {
          id: user._id,
          email: user.email,
          displayName: user.displayName,
          role: user.role,
          avatarBase64: user.avatarBase64 || '',
        },
      },
    });
  } catch (e) {
    console.error('Login error:', e);
    return res.status(500).json({ ok: false, error: 'Server error' });
  }
});

// ========== FORGOT PASSWORD ==========
router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body || {};
    const normalizedEmail = String(email || '').trim().toLowerCase();

    if (!normalizedEmail || !EMAIL_REGEX.test(normalizedEmail)) {
      return res.status(400).json({ ok: false, error: 'Email қажет' });
    }

    const user = await User.findOne({ email: normalizedEmail });
    if (!user) {
      // Қауіпсіздік үшін табылмаса да сәтті деп қайтарамыз
      return res.json({
        ok: true,
        message: 'Егер email тіркелген болса, код жіберілді.',
        ...(process.env.NODE_ENV === 'development' && {
          debug: 'USER_NOT_FOUND',
        }),
      });
    }

    // 4 таңбалы код генерациялаймыз
    const code = Math.floor(1000 + Math.random() * 9000).toString();

    user.resetCode = code;
    user.resetCodeExpires = new Date(Date.now() + 10 * 60 * 1000); // 10 минут
    await user.save();

    let mailResult = { ok: false, error: 'UNKNOWN' };
    try {
      mailResult = await sendPasswordResetCodeEmail(normalizedEmail, code);
    } catch (mailErr) {
      mailResult = {
        ok: false,
        error: mailErr?.message || String(mailErr),
      };
    }

    if (!mailResult.ok) {
      console.error(
        `forgot-password mail send error for ${normalizedEmail}:`,
        mailResult.error
      );
      return res.status(502).json({
        ok: false,
        error: 'Email жіберу мүмкін болмады. Почта баптауларын тексеріңіз.',
        ...(process.env.NODE_ENV === 'development' && {
          debug: String(mailResult.error || ''),
        }),
      });
    }

    return res.json({
      ok: true,
      message: 'Код email-ге жіберілді',
    });
  } catch (e) {
    console.error('forgot-password error:', e);
    return res.status(500).json({ ok: false, error: 'Қате орын алды' });
  }
});

// ========== VERIFY CODE AND RESET PASSWORD ==========
router.post('/reset-password', async (req, res) => {
  try {
    const { email, code, newPassword } = req.body || {};
    const normalizedEmail = String(email || '').trim().toLowerCase();

    if (!normalizedEmail || !EMAIL_REGEX.test(normalizedEmail) || !code || !newPassword) {
      return res.status(400).json({ 
        ok: false, 
        error: 'Email, код және жаңа құпия сөз қажет' 
      });
    }

    const passwordError = validatePassword(newPassword);
    if (passwordError) {
      return res.status(400).json({ 
        ok: false, 
        error: passwordError, 
      });
    }

    const user = await User.findOne({ 
      email: normalizedEmail,
      resetCode: code,
      resetCodeExpires: { $gt: Date.now() }
    });

    if (!user) {
      return res.status(400).json({ 
        ok: false, 
        error: 'Қате код немесе кодтың мерзімі аяқталған' 
      });
    }

    // Жаңа пароль орнату
    user.passwordHash = await bcrypt.hash(newPassword, 10);
    user.resetCode = undefined;
    user.resetCodeExpires = undefined;
    await user.save();

    return res.json({
      ok: true,
      message: 'Құпия сөз сәтті жаңартылды'
    });
  } catch (e) {
    console.error('reset-password error:', e);
    return res.status(500).json({ ok: false, error: 'Қате орын алды' });
  }
});

module.exports = router;
