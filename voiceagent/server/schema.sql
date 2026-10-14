DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS demo_slots;
DROP TABLE IF EXISTS students;
DROP TABLE IF EXISTS batches;
DROP TABLE IF EXISTS teachers;


CREATE TABLE teachers (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    style TEXT NOT NULL
);

CREATE TABLE batches (
    id INTEGER PRIMARY KEY,
    subject TEXT NOT NULL,
    level TEXT NOT NULL,
    language TEXT NOT NULL,
    pace TEXT NOT NULL,
    days TEXT NOT NULL,
    start_time TEXT NOT NULL,
    weeks INTEGER NOT NULL,
    fee INTEGER NOT NULL,
    seats_total INTEGER NOT NULL,
    seats_left INTEGER NOT NULL,
    teacher_id INTEGER NOT NULL REFERENCES teachers(id)
);

CREATE TABLE students (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT UNIQUE NOT NULL,
    level TEXT,
    language_pref TEXT,
    pace_pref TEXT,
    time_pref TEXT,
    status TEXT NOT NULL DEFAULT 'new'
);

CREATE TABLE demo_slots (
    id INTEGER PRIMARY KEY,
    batch_id INTEGER NOT NULL REFERENCES batches(id),
    slot_at TEXT NOT NULL,
    seats_total INTEGER NOT NULL,
    seats_left INTEGER NOT NULL,
    UNIQUE(batch_id, slot_at)
);

CREATE TABLE bookings (
    id INTEGER PRIMARY KEY,
    student_id INTEGER NOT NULL REFERENCES students(id),
    batch_id INTEGER NOT NULL REFERENCES batches(id),
    slot_id INTEGER NOT NULL REFERENCES demo_slots(id),
    status TEXT NOT NULL DEFAULT 'booked',
    created_at TEXT NOT NULL,
    UNIQUE(student_id, slot_id)
);

CREATE TABLE payments (
    id INTEGER PRIMARY KEY,
    student_id INTEGER NOT NULL REFERENCES students(id),
    batch_id INTEGER NOT NULL REFERENCES batches(id),
    amount INTEGER NOT NULL,
    plan TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL,
    link TEXT NOT NULL
);

CREATE TABLE messages (
    id INTEGER PRIMARY KEY,
    student_id INTEGER NOT NULL REFERENCES students(id),
    template TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_batches_lookup ON batches(subject, level, language);
CREATE INDEX idx_slot_batch ON demo_slots(batch_id, seats_left);