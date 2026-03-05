const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const { createSmtpTransport, getSmtpConfig } = require('./config/smtp');

const { user: SMTP_USER, pass: SMTP_PASS, from: SMTP_FROM } = getSmtpConfig();
const TEST_EMAIL_TO = String(process.env.TEST_EMAIL_TO || '').trim();
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

if (!SMTP_USER || !SMTP_PASS) {
  console.error('Set SMTP_USER/SMTP_PASS in backend/.env.');
  process.exit(1);
}

if (!TEST_EMAIL_TO || !EMAIL_REGEX.test(TEST_EMAIL_TO)) {
  console.error('Set a valid TEST_EMAIL_TO in backend/.env.');
  process.exit(1);
}

const transporter = createSmtpTransport();

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
