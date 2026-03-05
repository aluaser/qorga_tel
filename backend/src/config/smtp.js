const nodemailer = require('nodemailer');

function getSmtpConfig() {
  const service = String(process.env.SMTP_SERVICE || 'gmail').trim();
  const user = String(process.env.SMTP_USER || '').trim();
  const rawPass = String(process.env.SMTP_PASS || '').trim();
  const from = String(process.env.SMTP_FROM || user).trim();

  // Gmail app passwords are often copied with visual spaces.
  const pass = service.toLowerCase() === 'gmail'
    ? rawPass.replace(/\s+/g, '')
    : rawPass;

  return {
    service,
    user,
    pass,
    from,
  };
}

function createSmtpTransport() {
  const cfg = getSmtpConfig();
  if (!cfg.user || !cfg.pass) return null;

  return nodemailer.createTransport({
    service: cfg.service,
    auth: {
      user: cfg.user,
      pass: cfg.pass,
    },
  });
}

module.exports = {
  createSmtpTransport,
  getSmtpConfig,
};
