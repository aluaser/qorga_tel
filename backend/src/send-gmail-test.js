require('dotenv').config();
const nodemailer = require('nodemailer');

const SMTP_SERVICE = String(process.env.SMTP_SERVICE || 'gmail').trim();
const SMTP_USER = String(process.env.SMTP_USER || '').trim();
const SMTP_PASS = String(process.env.SMTP_PASS || '').trim();
const SMTP_FROM = String(process.env.SMTP_FROM || SMTP_USER).trim();
const TEST_EMAIL_TO = String(process.env.TEST_EMAIL_TO || '').trim();

if (!SMTP_USER || !SMTP_PASS) {
  console.error('Set SMTP_USER/SMTP_PASS in backend/.env.');
  process.exit(1);
}

if (!TEST_EMAIL_TO) {
  console.error('Set TEST_EMAIL_TO in backend/.env.');
  process.exit(1);
}

const transporter = nodemailer.createTransport({
  service: SMTP_SERVICE,
  auth: {
    user: SMTP_USER,
    pass: SMTP_PASS,
  },
});

async function run() {
  try {
    const result = await transporter.sendMail({
      from: SMTP_FROM,
      to: TEST_EMAIL_TO,
      subject: 'Qorga Gmail SMTP test',
      text: 'This is a Gmail SMTP test email from Qorga backend.',
      html: '<p>This is a <strong>Gmail SMTP</strong> test email from Qorga backend.</p>',
    });

    if (!result?.messageId) {
      console.error('Gmail SMTP send failed: messageId is missing');
      process.exit(1);
    }

    console.log('Email sent via Gmail SMTP:', result.messageId);
  } catch (error) {
    console.error('Gmail SMTP send failed:', error?.message || error);
    process.exit(1);
  }
}

run();
