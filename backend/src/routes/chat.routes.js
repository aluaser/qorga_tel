const express = require('express');
const router = express.Router();
const axios = require('axios');
const mongoose = require('mongoose');
const User = require('../models/user');
const ChatMessage = require('../models/ChatMessage');
const { emitChatMessage } = require('../socket/chat.socket');

const DEFAULT_PSYCHOLOGIST_EMAIL = (process.env.DEFAULT_PSYCHOLOGIST_EMAIL || '')
  .trim()
  .toLowerCase();
const DEFAULT_PSYCHOLOGIST_GREETING =
  (
    process.env.DEFAULT_PSYCHOLOGIST_GREETING ||
    'Сәлем! Менің атым — Қабыкен Алтынай Амангелдіқызы. Мен Qopga қосымшасының психологымын. Егер сізге менің көмегім қажет болса, кез келген уақытта маған жаза аласыз.'
  ).trim();

function isValidObjectId(id) {
  return mongoose.Types.ObjectId.isValid(id);
}

function normalizeId(id) {
  return String(id || '').trim();
}

function buildHumanChatId(a, b) {
  const ids = [normalizeId(a), normalizeId(b)].sort();
  return `human:${ids[0]}:${ids[1]}`;
}

function buildAiChatId(userId) {
  return `ai:${normalizeId(userId)}`;
}

function mapMessage(m) {
  return {
    id: m._id,
    chatId: m.chatId,
    chatType: m.chatType,
    senderType: m.senderType,
    recipientType: m.recipientType,
    senderId: m.senderId,
    recipientId: m.recipientId,
    text: m.text,
    createdAt: m.createdAt,
    read: m.read,
  };
}

async function findDefaultPsychologist() {
  if (DEFAULT_PSYCHOLOGIST_EMAIL) {
    const byConfiguredEmail = await User.findOne(
      { email: DEFAULT_PSYCHOLOGIST_EMAIL, role: 'psychologist' },
      { email: 1, displayName: 1, role: 1 }
    ).lean();
    if (byConfiguredEmail?._id) return byConfiguredEmail;
  }

  return User.findOne(
    { role: 'psychologist' },
    { email: 1, displayName: 1, role: 1 }
  )
    .sort({ createdAt: 1 })
    .lean();
}

async function ensureDefaultPsychologistGreeting({ userId, psychologistId, io }) {
  const uid = normalizeId(userId);
  const pid = normalizeId(psychologistId);
  if (!isValidObjectId(uid) || !isValidObjectId(pid) || uid === pid) {
    return null;
  }

  const chatId = buildHumanChatId(uid, pid);
  const hasMessages = await ChatMessage.exists({
    chatId,
    $or: [{ chatType: 'human' }, { chatType: { $exists: false } }],
  });

  if (hasMessages) {
    return null;
  }

  const greeting = await ChatMessage.create({
    chatId,
    chatType: 'human',
    senderType: 'user',
    recipientType: 'user',
    senderId: pid,
    recipientId: uid,
    text: DEFAULT_PSYCHOLOGIST_GREETING,
    read: false,
  });

  emitChatMessage(io, greeting);
  return greeting;
}

async function generateAiReply(message) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return 'Серверде ИИ баптауы орнатылмаған (GEMINI_API_KEY).';
  }

  const model = process.env.GEMINI_MODEL || 'gemini-2.5-flash';
  const url = `https://generativelanguage.googleapis.com/v1/models/${model}:generateContent`;

  const response = await axios.post(
    `${url}?key=${apiKey}`,
    {
      contents: [
        {
          role: 'user',
          parts: [
            {
              text:
                'Сен студенттерге арналған психологиялық көмекші чат-ботсың. ' +
                'Жылы, түсіністікпен, қысқа және қарапайым қазақ тілінде жауап бер. ' +
                'Қауіпті кеңестер берме, өзіне қол жұмсау туралы нұсқаулық жазба. ' +
                'Міне, пайдаланушының хабары: ' +
                message,
            },
          ],
        },
      ],
    },
    {
      headers: {
        'Content-Type': 'application/json',
      },
    }
  );

  let reply = 'Кешіріңіз, жауап бере алмадым.';
  const candidates = response.data.candidates || [];
  if (
    candidates.length > 0 &&
    candidates[0].content &&
    Array.isArray(candidates[0].content.parts)
  ) {
    reply = candidates[0].content.parts
      .map((p) => p.text || '')
      .join(' ')
      .trim();
  }

  return reply || 'Кешіріңіз, жауап бере алмадым.';
}

async function getLastMessageForChat(chatId, userId, peerId) {
  const filter = chatId.startsWith('ai:')
    ? { chatId }
    : {
        $or: [
          { senderId: userId, recipientId: peerId },
          { senderId: peerId, recipientId: userId },
        ],
      };

  return ChatMessage.findOne(filter, { text: 1, createdAt: 1, senderType: 1, senderId: 1 })
    .sort({ createdAt: -1 })
    .lean();
}

// New chats list endpoint for WhatsApp-like UX.
// GET /chat/list?userId=...
router.get('/list', async (req, res) => {
  try {
    const io = req.app.get('io');
    const userId = normalizeId(req.query.userId);
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ ok: false, error: 'Valid userId is required' });
    }

    const me = await User.findById(userId, { role: 1, email: 1, displayName: 1 }).lean();
    if (!me) {
      return res.status(404).json({ ok: false, error: 'User not found' });
    }

    const uid = new mongoose.Types.ObjectId(userId);

    if (me.role === 'psychologist') {
      const dialogs = await ChatMessage.aggregate([
        {
          $match: {
            $or: [{ chatType: 'human' }, { chatType: { $exists: false } }],
            $and: [{ $or: [{ senderId: uid }, { recipientId: uid }] }],
          },
        },
        { $sort: { createdAt: -1 } },
        {
          $addFields: {
            peerId: {
              $cond: [{ $eq: ['$senderId', uid] }, '$recipientId', '$senderId'],
            },
          },
        },
        {
          $group: {
            _id: '$peerId',
            lastMessage: { $first: '$text' },
            lastAt: { $first: '$createdAt' },
            unreadCount: {
              $sum: {
                $cond: [
                  {
                    $and: [
                      { $eq: ['$recipientId', uid] },
                      { $eq: ['$read', false] },
                    ],
                  },
                  1,
                  0,
                ],
              },
            },
          },
        },
        { $sort: { lastAt: -1 } },
      ]);

      const users = await User.find(
        { role: 'user', _id: { $ne: uid } },
        { email: 1, displayName: 1, role: 1 }
      )
        .sort({ createdAt: -1 })
        .lean();

      const dialogMap = new Map(dialogs.map((d) => [String(d._id), d]));

      const items = users
        .map((u) => {
          const key = String(u._id);
          const dialog = dialogMap.get(key);
          return {
            chatId: buildHumanChatId(userId, key),
            title: u.displayName || u.email || 'Пайдаланушы',
            subtitle: dialog?.lastMessage || 'Жаңа диалог',
            lastAt: dialog?.lastAt || null,
            unreadCount: dialog?.unreadCount || 0,
            peer: {
              id: u._id,
              email: u.email,
              displayName: u.displayName || u.email,
              role: u.role,
            },
            kind: 'human',
          };
        })
        .sort((a, b) => {
          const at = a.lastAt ? new Date(a.lastAt).getTime() : 0;
          const bt = b.lastAt ? new Date(b.lastAt).getTime() : 0;
          return bt - at;
        });

      return res.json({ ok: true, items, meRole: me.role });
    }

    const psychologist = await findDefaultPsychologist();
    const aiChatId = buildAiChatId(userId);
    const aiLast = await getLastMessageForChat(aiChatId, userId, null);

    const items = [
      {
        chatId: aiChatId,
        title: 'ИИ-помощник',
        subtitle: aiLast?.text || 'Напишите сообщение',
        lastAt: aiLast?.createdAt || null,
        unreadCount: 0,
        kind: 'ai',
        peer: {
          id: 'ai',
          email: null,
          displayName: 'ИИ-помощник',
          role: 'ai',
        },
      },
    ];

    if (psychologist?._id) {
      const pid = String(psychologist._id);
      await ensureDefaultPsychologistGreeting({
        userId,
        psychologistId: pid,
        io,
      });
      const lastHuman = await getLastMessageForChat(
        buildHumanChatId(userId, pid),
        userId,
        pid
      );

      const unreadCount = await ChatMessage.countDocuments({
        senderId: new mongoose.Types.ObjectId(pid),
        recipientId: uid,
        read: false,
      });

      items.push({
        chatId: buildHumanChatId(userId, pid),
        title: psychologist.displayName || psychologist.email || 'Психолог',
        subtitle: lastHuman?.text || 'Свяжитесь с психологом',
        lastAt: lastHuman?.createdAt || null,
        unreadCount,
        kind: 'human',
        peer: {
          id: psychologist._id,
          email: psychologist.email,
          displayName: psychologist.displayName || psychologist.email,
          role: psychologist.role || 'psychologist',
        },
      });
    }

    items.sort((a, b) => {
      const at = a.lastAt ? new Date(a.lastAt).getTime() : 0;
      const bt = b.lastAt ? new Date(b.lastAt).getTime() : 0;
      return bt - at;
    });

    return res.json({ ok: true, items, meRole: me.role });
  } catch (err) {
    console.error('chat list error:', err);
    return res.status(500).json({ ok: false, error: 'Failed to load chats' });
  }
});

// Backward-compatible endpoint.
// GET /chat/users?role=psychologist&userId=...
router.get('/users', async (req, res) => {
  try {
    const roleParam = (req.query.role || 'psychologist').trim();
    const userId = (req.query.userId || '').trim();

    const roles = roleParam
      .split(',')
      .map((r) => r.trim())
      .filter(Boolean);

    const query =
      roles.length > 1 ? { role: { $in: roles } } : { role: roles[0] || 'psychologist' };

    if (isValidObjectId(userId)) {
      query._id = { $ne: userId };
    }

    const users = await User.find(query, { email: 1, displayName: 1, role: 1 })
      .sort({ createdAt: -1 })
      .lean();

    return res.json({
      ok: true,
      items: users.map((u) => ({
        id: u._id,
        email: u.email,
        displayName: u.displayName || u.email,
        role: u.role,
      })),
    });
  } catch (err) {
    console.error('chat users error:', err);
    return res.status(500).json({ ok: false, error: 'Failed to load users' });
  }
});

// Backward-compatible endpoint.
// GET /chat/dialogs?userId=...
router.get('/dialogs', async (req, res) => {
  try {
    const userId = normalizeId(req.query.userId);
    if (!isValidObjectId(userId)) {
      return res.status(400).json({ ok: false, error: 'Valid userId is required' });
    }

    const uid = new mongoose.Types.ObjectId(userId);

    const dialogs = await ChatMessage.aggregate([
      {
        $match: {
          $or: [{ chatType: 'human' }, { chatType: { $exists: false } }],
          $and: [{ $or: [{ senderId: uid }, { recipientId: uid }] }],
        },
      },
      { $sort: { createdAt: -1 } },
      {
        $addFields: {
          peerId: {
            $cond: [{ $eq: ['$senderId', uid] }, '$recipientId', '$senderId'],
          },
        },
      },
      {
        $group: {
          _id: '$peerId',
          lastMessage: { $first: '$text' },
          lastAt: { $first: '$createdAt' },
        },
      },
      { $sort: { lastAt: -1 } },
      {
        $lookup: {
          from: 'users',
          localField: '_id',
          foreignField: '_id',
          as: 'peer',
        },
      },
      { $unwind: '$peer' },
      {
        $project: {
          _id: 0,
          peerId: '$_id',
          chatId: {
            $concat: [
              'human:',
              {
                $cond: [
                  { $lt: [{ $toString: '$_id' }, userId] },
                  { $toString: '$_id' },
                  userId,
                ],
              },
              ':',
              {
                $cond: [
                  { $lt: [{ $toString: '$_id' }, userId] },
                  userId,
                  { $toString: '$_id' },
                ],
              },
            ],
          },
          lastMessage: 1,
          lastAt: 1,
          peer: {
            id: '$peer._id',
            email: '$peer.email',
            displayName: '$peer.displayName',
            role: '$peer.role',
          },
        },
      },
    ]);

    return res.json({ ok: true, items: dialogs });
  } catch (err) {
    console.error('chat dialogs error:', err);
    return res.status(500).json({ ok: false, error: 'Failed to load dialogs' });
  }
});

// GET /chat/messages?userId=...&chatId=... OR /chat/messages?userId=...&peerId=...
router.get('/messages', async (req, res) => {
  try {
    const userId = normalizeId(req.query.userId);
    const peerId = normalizeId(req.query.peerId);
    let chatId = normalizeId(req.query.chatId);
    const limit = Math.min(parseInt(req.query.limit || '100', 10), 300);

    if (!isValidObjectId(userId)) {
      return res.status(400).json({ ok: false, error: 'Valid userId is required' });
    }

    const uid = new mongoose.Types.ObjectId(userId);

    if (!chatId) {
      if (!isValidObjectId(peerId)) {
        return res.status(400).json({ ok: false, error: 'chatId or valid peerId is required' });
      }
      chatId = buildHumanChatId(userId, peerId);
    }

    const isAiChat = chatId.startsWith('ai:');

    if (isAiChat) {
      if (chatId !== buildAiChatId(userId)) {
        return res.status(403).json({ ok: false, error: 'Forbidden chatId' });
      }

      const messages = await ChatMessage.find(
        { chatId },
        {
          chatId: 1,
          chatType: 1,
          senderType: 1,
          recipientType: 1,
          senderId: 1,
          recipientId: 1,
          text: 1,
          createdAt: 1,
          read: 1,
        }
      )
        .sort({ createdAt: 1 })
        .limit(limit)
        .lean();

      return res.json({ ok: true, items: messages.map(mapMessage) });
    }

    const messages = await ChatMessage.find(
      {
        $or: [{ chatType: 'human' }, { chatType: { $exists: false } }],
        $and: [
          {
            $or: [
              { senderId: uid, chatId },
              { recipientId: uid, chatId },
            ],
          },
        ],
      },
      {
        chatId: 1,
        chatType: 1,
        senderType: 1,
        recipientType: 1,
        senderId: 1,
        recipientId: 1,
        text: 1,
        createdAt: 1,
        read: 1,
      }
    )
      .sort({ createdAt: 1 })
      .limit(limit)
      .lean();

    await ChatMessage.updateMany(
      {
        chatId,
        recipientId: uid,
        read: false,
      },
      { $set: { read: true } }
    );

    return res.json({ ok: true, items: messages.map(mapMessage) });
  } catch (err) {
    console.error('chat messages error:', err);
    return res.status(500).json({ ok: false, error: 'Failed to load messages' });
  }
});

// POST /chat/messages
router.post('/messages', async (req, res) => {
  try {
    const io = req.app.get('io');
    const senderId = normalizeId(req.body?.senderId);
    const recipientId = normalizeId(req.body?.recipientId);
    let chatId = normalizeId(req.body?.chatId);
    const text = normalizeId(req.body?.text);

    if (!isValidObjectId(senderId)) {
      return res.status(400).json({ ok: false, error: 'Valid senderId is required' });
    }

    if (!text) {
      return res.status(400).json({ ok: false, error: 'Message text is required' });
    }

    if (!chatId && !recipientId) {
      return res.status(400).json({ ok: false, error: 'chatId or recipientId is required' });
    }

    if (!chatId && recipientId) {
      if (!isValidObjectId(recipientId)) {
        return res.status(400).json({ ok: false, error: 'Valid recipientId is required' });
      }
      chatId = buildHumanChatId(senderId, recipientId);
    }

    const isAiChat = chatId.startsWith('ai:');
    if (isAiChat) {
      if (chatId !== buildAiChatId(senderId)) {
        return res.status(403).json({ ok: false, error: 'Forbidden ai chatId' });
      }

      const userMessage = await ChatMessage.create({
        chatId,
        chatType: 'ai',
        senderType: 'user',
        recipientType: 'ai',
        senderId,
        recipientId: null,
        text,
        read: true,
      });

      let replyText = 'Кешіріңіз, жауап бере алмадым.';
      try {
        replyText = await generateAiReply(text);
      } catch (err) {
        console.error('Gemini error:', err.response?.data || err.message);
        replyText =
          'Серверде қате орын алды. Кейінірек қайталап көріңіз немесе басқа сұрақ қойып көріңіз.';
      }

      const botMessage = await ChatMessage.create({
        chatId,
        chatType: 'ai',
        senderType: 'ai',
        recipientType: 'user',
        senderId: null,
        recipientId: senderId,
        text: replyText,
        read: false,
      });

      emitChatMessage(io, userMessage);
      emitChatMessage(io, botMessage);

      return res.status(201).json({
        ok: true,
        item: mapMessage(userMessage),
        aiReply: mapMessage(botMessage),
      });
    }

    if (!isValidObjectId(recipientId)) {
      return res.status(400).json({ ok: false, error: 'Valid recipientId is required for human chat' });
    }

    const fixedChatId = buildHumanChatId(senderId, recipientId);

    const msg = await ChatMessage.create({
      chatId: fixedChatId,
      chatType: 'human',
      senderType: 'user',
      recipientType: 'user',
      senderId,
      recipientId,
      text,
    });

    emitChatMessage(io, msg);

    return res.status(201).json({ ok: true, item: mapMessage(msg) });
  } catch (err) {
    console.error('chat send message error:', err);
    return res.status(500).json({ ok: false, error: 'Failed to send message' });
  }
});

// Legacy AI helper endpoint.
router.post('/send', async (req, res) => {
  try {
    const message = normalizeId(req.body?.message);

    if (!message) {
      return res.status(400).json({ reply: 'Алдымен сұрағыңызды жазыңыз.' });
    }

    const reply = await generateAiReply(message);
    return res.json({ reply });
  } catch (err) {
    console.error('Gemini error:', err.response?.data || err.message);
    return res.status(500).json({
      reply:
        'Серверде қате орын алды. Кейінірек қайталап көріңіз немесе басқа сұрақ қойып көріңіз.',
    });
  }
});

module.exports = router;
