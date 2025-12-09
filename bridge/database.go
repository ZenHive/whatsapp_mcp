package main

import (
	"database/sql"
	"fmt"
	"os"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

// NewMessageStore initializes and returns a new MessageStore
func NewMessageStore() (*MessageStore, error) {
	// Create directory for database if it doesn't exist
	if err := os.MkdirAll("store", 0755); err != nil {
		return nil, fmt.Errorf("failed to create store directory: %v", err)
	}

	// Open SQLite database for messages
	db, err := sql.Open("sqlite3", "file:store/messages.db?_foreign_keys=on")
	if err != nil {
		return nil, fmt.Errorf("failed to open message database: %v", err)
	}

	// Create tables if they don't exist
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS chats (
			jid TEXT PRIMARY KEY,
			name TEXT,
			last_message_time TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS messages (
			id TEXT,
			chat_jid TEXT,
			sender TEXT,
			content TEXT,
			timestamp TIMESTAMP,
			is_from_me BOOLEAN,
			media_type TEXT,
			filename TEXT,
			url TEXT,
			media_key BLOB,
			file_sha256 BLOB,
			file_enc_sha256 BLOB,
			file_length INTEGER,
			PRIMARY KEY (id, chat_jid),
			FOREIGN KEY (chat_jid) REFERENCES chats(jid)
		);

		CREATE TABLE IF NOT EXISTS contacts (
			jid TEXT PRIMARY KEY,
			phone TEXT,
			name TEXT,
			updated_at TIMESTAMP
		);
	`)
	if err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to create tables: %v", err)
	}

	return &MessageStore{db: db}, nil
}

// Close the database connection
func (store *MessageStore) Close() error {
	return store.db.Close()
}

// StoreChat stores a chat in the database
func (store *MessageStore) StoreChat(jid, name string, lastMessageTime time.Time) error {
	_, err := store.db.Exec(
		"INSERT OR REPLACE INTO chats (jid, name, last_message_time) VALUES (?, ?, ?)",
		jid, name, lastMessageTime,
	)
	return err
}

// StoreMessage stores a message in the database
func (store *MessageStore) StoreMessage(id, chatJID, sender, content string, timestamp time.Time, isFromMe bool,
	mediaType, filename, url string, mediaKey, fileSHA256, fileEncSHA256 []byte, fileLength uint64) error {
	// Only store if there's actual content or media
	if content == "" && mediaType == "" {
		return nil
	}

	_, err := store.db.Exec(
		`INSERT OR REPLACE INTO messages
		(id, chat_jid, sender, content, timestamp, is_from_me, media_type, filename, url, media_key, file_sha256, file_enc_sha256, file_length)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, chatJID, sender, content, timestamp, isFromMe, mediaType, filename, url, mediaKey, fileSHA256, fileEncSHA256, fileLength,
	)
	return err
}

// GetMessages retrieves messages from a chat
func (store *MessageStore) GetMessages(chatJID string, limit int) ([]Message, error) {
	rows, err := store.db.Query(
		"SELECT sender, content, timestamp, is_from_me, media_type, filename FROM messages WHERE chat_jid = ? ORDER BY timestamp DESC LIMIT ?",
		chatJID, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []Message
	for rows.Next() {
		var msg Message
		var timestamp time.Time
		err := rows.Scan(&msg.Sender, &msg.Content, &timestamp, &msg.IsFromMe, &msg.MediaType, &msg.Filename)
		if err != nil {
			return nil, err
		}
		msg.Time = timestamp
		messages = append(messages, msg)
	}

	return messages, nil
}

// StoreContact stores a contact in the database
func (store *MessageStore) StoreContact(jid, phone, name string) error {
	_, err := store.db.Exec(
		"INSERT OR REPLACE INTO contacts (jid, phone, name, updated_at) VALUES (?, ?, ?, ?)",
		jid, phone, name, time.Now().UTC(),
	)
	return err
}

// GetContact retrieves a contact by JID from the contacts cache
func (store *MessageStore) GetContact(jid string) (phone, name string, found bool) {
	err := store.db.QueryRow(
		"SELECT phone, name FROM contacts WHERE jid = ?",
		jid,
	).Scan(&phone, &name)
	if err != nil {
		return "", "", false
	}
	return phone, name, true
}

// GetChats retrieves all chats
func (store *MessageStore) GetChats() (map[string]time.Time, error) {
	rows, err := store.db.Query("SELECT jid, last_message_time FROM chats ORDER BY last_message_time DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	chats := make(map[string]time.Time)
	for rows.Next() {
		var jid string
		var lastMessageTime time.Time
		err := rows.Scan(&jid, &lastMessageTime)
		if err != nil {
			return nil, err
		}
		chats[jid] = lastMessageTime
	}

	return chats, nil
}

// MergeChats merges all messages from sourceJID into targetJID, then deletes the source chat.
// Returns the number of messages moved, or an error if either chat doesn't exist.
func (store *MessageStore) MergeChats(sourceJID, targetJID string) (int64, error) {
	// Start a transaction
	tx, err := store.db.Begin()
	if err != nil {
		return 0, fmt.Errorf("failed to begin transaction: %v", err)
	}
	defer tx.Rollback() // Will be ignored if tx.Commit() succeeds

	// Verify source chat exists
	var sourceExists bool
	err = tx.QueryRow("SELECT 1 FROM chats WHERE jid = ?", sourceJID).Scan(&sourceExists)
	if err == sql.ErrNoRows {
		return 0, fmt.Errorf("source chat does not exist: %s", sourceJID)
	}
	if err != nil {
		return 0, fmt.Errorf("failed to check source chat: %v", err)
	}

	// Verify target chat exists
	var targetExists bool
	err = tx.QueryRow("SELECT 1 FROM chats WHERE jid = ?", targetJID).Scan(&targetExists)
	if err == sql.ErrNoRows {
		return 0, fmt.Errorf("target chat does not exist: %s", targetJID)
	}
	if err != nil {
		return 0, fmt.Errorf("failed to check target chat: %v", err)
	}

	// Move all messages from source to target
	result, err := tx.Exec("UPDATE messages SET chat_jid = ? WHERE chat_jid = ?", targetJID, sourceJID)
	if err != nil {
		return 0, fmt.Errorf("failed to move messages: %v", err)
	}

	messagesMoved, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("failed to get rows affected: %v", err)
	}

	// Store the LID→phone link in contacts table for future auto-merge
	// The source is typically the @lid JID, target is the @s.whatsapp.net JID
	// Extract phone number from target JID (e.g., "14155554567@s.whatsapp.net" → "14155554567")
	if strings.HasSuffix(targetJID, "@s.whatsapp.net") {
		phone := strings.Split(targetJID, "@")[0]
		// Store the link: source @lid JID → target phone number
		_, err = tx.Exec(
			"INSERT OR REPLACE INTO contacts (jid, phone, name, updated_at) VALUES (?, ?, ?, ?)",
			sourceJID, phone, "", time.Now().UTC(),
		)
		if err != nil {
			return 0, fmt.Errorf("failed to store contact link: %v", err)
		}
	}

	// Delete the source chat
	_, err = tx.Exec("DELETE FROM chats WHERE jid = ?", sourceJID)
	if err != nil {
		return 0, fmt.Errorf("failed to delete source chat: %v", err)
	}

	// Commit the transaction
	if err := tx.Commit(); err != nil {
		return 0, fmt.Errorf("failed to commit transaction: %v", err)
	}

	return messagesMoved, nil
}

// StoreMediaInfo stores additional media info in the database
func (store *MessageStore) StoreMediaInfo(id, chatJID, url string, mediaKey, fileSHA256, fileEncSHA256 []byte, fileLength uint64) error {
	_, err := store.db.Exec(
		"UPDATE messages SET url = ?, media_key = ?, file_sha256 = ?, file_enc_sha256 = ?, file_length = ? WHERE id = ? AND chat_jid = ?",
		url, mediaKey, fileSHA256, fileEncSHA256, fileLength, id, chatJID,
	)
	return err
}

// GetMediaInfo retrieves media info from the database
func (store *MessageStore) GetMediaInfo(id, chatJID string) (string, string, string, []byte, []byte, []byte, uint64, error) {
	var mediaType, filename, url string
	var mediaKey, fileSHA256, fileEncSHA256 []byte
	var fileLength uint64

	err := store.db.QueryRow(
		"SELECT media_type, filename, url, media_key, file_sha256, file_enc_sha256, file_length FROM messages WHERE id = ? AND chat_jid = ?",
		id, chatJID,
	).Scan(&mediaType, &filename, &url, &mediaKey, &fileSHA256, &fileEncSHA256, &fileLength)

	return mediaType, filename, url, mediaKey, fileSHA256, fileEncSHA256, fileLength, err
}

// GetChatName retrieves the name of a chat by JID
func (store *MessageStore) GetChatName(chatJID string) string {
	var name string
	err := store.db.QueryRow("SELECT name FROM chats WHERE jid = ?", chatJID).Scan(&name)
	if err != nil {
		return ""
	}
	return name
}

// GetBasicMediaInfo retrieves just media_type and filename from a message (fallback for incomplete media info)
func (store *MessageStore) GetBasicMediaInfo(messageID, chatJID string) (mediaType, filename string, err error) {
	err = store.db.QueryRow(
		"SELECT media_type, filename FROM messages WHERE id = ? AND chat_jid = ?",
		messageID, chatJID,
	).Scan(&mediaType, &filename)
	return
}
