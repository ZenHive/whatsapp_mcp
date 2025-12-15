package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"github.com/mdp/qrterminal"

	"go.mau.fi/whatsmeow"
	waProto "go.mau.fi/whatsmeow/binary/proto"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"
)

func main() {
	// Set up logger
	logger := waLog.Stdout("Client", "INFO", true)
	logger.Infof("Starting WhatsApp client...")

	// Create database connection for storing session data
	dbLog := waLog.Stdout("Database", "INFO", true)

	// Create directory for database if it doesn't exist
	if err := os.MkdirAll("store", 0755); err != nil {
		logger.Errorf("Failed to create store directory: %v", err)
		return
	}

	container, err := sqlstore.New(context.Background(), "sqlite3", "file:store/whatsapp.db?_foreign_keys=on", dbLog)
	if err != nil {
		logger.Errorf("Failed to connect to database: %v", err)
		return
	}

	// Set custom device name before getting/creating device
	store.DeviceProps.Os = proto.String(DeviceName)
	store.DeviceProps.PlatformType = waProto.DeviceProps_DESKTOP.Enum()

	// Configure history sync to request more data
	// NOTE: These settings are sent during pairing and affect what WhatsApp sends
	// Changing these after initial pairing requires deleting store/ and re-scanning QR
	store.DeviceProps.RequireFullSync = proto.Bool(true) // Request full sync instead of recent only
	if store.DeviceProps.HistorySyncConfig != nil {
		store.DeviceProps.HistorySyncConfig.SupportGroupHistory = proto.Bool(true) // Include group history
	}

	// Get device store - This contains session information
	deviceStore, err := container.GetFirstDevice(context.Background())
	if err != nil {
		if err == sql.ErrNoRows {
			// No device exists, create one
			deviceStore = container.NewDevice()
			logger.Infof("Created new device")
		} else {
			logger.Errorf("Failed to get device: %v", err)
			return
		}
	}

	// Create client instance
	client := whatsmeow.NewClient(deviceStore, logger)
	if client == nil {
		logger.Errorf("Failed to create WhatsApp client")
		return
	}

	// Initialize message store
	messageStore, err := NewMessageStore()
	if err != nil {
		logger.Errorf("Failed to initialize message store: %v", err)
		return
	}
	defer messageStore.Close()

	// Create reconnection manager
	reconnectManager := NewReconnectManager(client, logger)

	// Setup event handling for messages and history sync
	client.AddEventHandler(func(evt interface{}) {
		switch v := evt.(type) {
		case *events.Message:
			// Process regular messages
			handleMessage(context.Background(), client, messageStore, v, logger)

		case *events.HistorySync:
			// Process history sync events
			handleHistorySync(context.Background(), client, messageStore, v, logger)

		case *events.Connected:
			logger.Infof("Connected to WhatsApp")

		case *events.Disconnected:
			// Handle disconnection - attempt to reconnect
			logger.Warnf("Disconnected from WhatsApp")
			reconnectManager.StartReconnect("disconnected event received")

		case *events.LoggedOut:
			logger.Warnf("Device logged out, please scan QR code to log in again")
			// Don't attempt reconnection on logout - requires re-authentication

		case *events.StreamReplaced:
			// Another device took over the connection
			logger.Warnf("Stream replaced by another device")
			reconnectManager.StartReconnect("stream replaced by another device")

		case *events.TemporaryBan:
			// Temporary ban from WhatsApp
			logger.Errorf("Temporarily banned from WhatsApp for %v: %s", v.Expire, v.Code)
			// Don't reconnect during ban - will fail anyway

		case *events.ConnectFailure:
			// Connection attempt failed
			logger.Warnf("Connection failure: %v (reason: %s)", v.Message, v.Reason)
			if v.Reason != events.ConnectFailureLoggedOut {
				reconnectManager.StartReconnect(fmt.Sprintf("connect failure: %s", v.Reason))
			}
		}
	})

	// Create channel to track connection success
	connected := make(chan bool, 1)

	// Connect to WhatsApp
	if client.Store.ID == nil {
		// No ID stored, this is a new client, need to pair with phone
		qrChan, _ := client.GetQRChannel(context.Background())
		err = client.Connect()
		if err != nil {
			logger.Errorf("Failed to connect: %v", err)
			return
		}

		// Print QR code for pairing with phone
		for evt := range qrChan {
			if evt.Event == "code" {
				fmt.Println("\nScan this QR code with your WhatsApp app:")
				qrterminal.GenerateHalfBlock(evt.Code, qrterminal.L, os.Stdout)
			} else if evt.Event == "success" {
				connected <- true
				break
			}
		}

		// Wait for connection
		select {
		case <-connected:
			fmt.Println("\nSuccessfully connected and authenticated!")
		case <-time.After(QRCodeTimeoutMinutes * time.Minute):
			logger.Errorf("Timeout waiting for QR code scan")
			return
		}
	} else {
		// Already logged in, just connect
		err = client.Connect()
		if err != nil {
			logger.Errorf("Failed to connect: %v", err)
			return
		}
		connected <- true
	}

	// Wait a moment for connection to stabilize
	time.Sleep(ConnectionStabilizeDelaySeconds * time.Second)

	if !client.IsConnected() {
		logger.Errorf("Failed to establish stable connection")
		return
	}

	fmt.Println("\n✓ Connected to WhatsApp! Type 'help' for commands.")

	// Start REST API server
	server := NewServer(client, messageStore, logger, getAPIPort())
	server.Start()

	// Create a channel to keep the main goroutine alive
	exitChan := make(chan os.Signal, 1)
	signal.Notify(exitChan, syscall.SIGINT, syscall.SIGTERM)

	fmt.Println("REST server is running. Press Ctrl+C to disconnect and exit.")

	// Wait for termination signal
	<-exitChan

	fmt.Println("Disconnecting...")
	// Stop reconnection attempts before disconnecting
	reconnectManager.Stop()
	// Disconnect client
	client.Disconnect()
}
