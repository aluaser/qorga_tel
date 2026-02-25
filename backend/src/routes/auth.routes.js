const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const User = require('../models/user');

const router = express.Router();

const ACCESS_TTL = process.env.ACCESS_TTL || '15m';
const JWT_SECRET = process.env.JWT_ACCESS_SECRET || 'dev-secret';

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

    const errors = [];
    if (!email || !/\S+@\S+\.\S+/.test(email)) errors.push('Некорректный email');
    if (!password || password.length < 6) errors.push('Пароль минимум 6 символов');
    if (displayName && displayName.length > 40) errors.push('displayName слишком длинный');
    if (errors.length) return res.status(400).json({ ok: false, errors });

    const exists = await User.findOne({ email });
    if (exists) {
      return res.status(409).json({ ok: false, error: 'Email уже зарегистрирован' });
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const user = await User.create({
      email,
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

    if (!email) {
      return res.status(400).json({ ok: false, error: 'Email required' });
    }

    const user = await User.findOne({ email });
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
    if (!email) {
      return res.status(400).json({ ok: false, error: 'Email қажет' });
    }

    const user = await User.findOne({ email });
    if (!user) {
      // Қауіпсіздік үшін табылмаса да сәтті деп қайтарамыз
      return res.json({ 
        ok: true, 
        message: 'Егер email тіркелген болса, код жіберілді.' 
      });
    }

    // 4 таңбалы код генерациялаймыз
    const code = Math.floor(1000 + Math.random() * 9000).toString();

    user.resetCode = code;
    user.resetCodeExpires = new Date(Date.now() + 10 * 60 * 1000); // 10 минут
    await user.save();

    // Тест режимінде консольға шығарамыз
    console.log('====================================');
    console.log(`PASSWORD RESET CODE FOR ${email}: ${code}`);
    console.log('====================================');

    return res.json({
      ok: true,
      message: 'Код жіберілді',
      // Тек тест режимде кодты қайтарамыз
      ...(process.env.NODE_ENV === 'development' && { testCode: code })
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

    if (!email || !code || !newPassword) {
      return res.status(400).json({ 
        ok: false, 
        error: 'Email, код және жаңа құпия сөз қажет' 
      });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({ 
        ok: false, 
        error: 'Құпия сөз кемінде 6 символдан тұруы қажет' 
      });
    }

    const user = await User.findOne({ 
      email,
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
