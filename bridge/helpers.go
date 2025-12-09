package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"

	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
)

// requireGET validates that the request method is GET
func requireGET(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return false
	}
	return true
}

// requirePOST validates that the request method is POST
func requirePOST(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return false
	}
	return true
}

// decodeJSON decodes JSON request body into the provided struct
func decodeJSON(w http.ResponseWriter, r *http.Request, v interface{}) bool {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		http.Error(w, "Invalid request format", http.StatusBadRequest)
		return false
	}
	return true
}

// requireField validates that a field is non-empty
func requireField(w http.ResponseWriter, value, fieldName string) bool {
	if value == "" {
		http.Error(w, fieldName+" is required", http.StatusBadRequest)
		return false
	}
	return true
}

// parseRecipientJID parses a JID, with fallback to s.whatsapp.net for phone numbers
func parseRecipientJID(recipient string) (types.JID, error) {
	if strings.Contains(recipient, "@") {
		return types.ParseJID(recipient)
	}
	return types.JID{
		User:   recipient,
		Server: "s.whatsapp.net",
	}, nil
}

// writeJSONError writes a JSON error response with the given status code
func writeJSONError(w http.ResponseWriter, statusCode int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(APIResponse{
		Success: false,
		Message: message,
	})
}

// writeJSONSuccess writes a JSON success response
func writeJSONSuccess(w http.ResponseWriter, message string) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(APIResponse{
		Success: true,
		Message: message,
	})
}

// writeJSON writes any value as JSON to the response writer.
// Sets Content-Type header and returns any encoding error.
func writeJSON(w http.ResponseWriter, v interface{}) error {
	w.Header().Set("Content-Type", "application/json")
	return json.NewEncoder(w).Encode(v)
}

// parseIntParam parses an integer from a string with default, min, and max values.
// If max is -1, no upper bound is enforced.
func parseIntParam(s string, defaultVal, minVal, maxVal int) int {
	if s == "" {
		return defaultVal
	}
	val, err := strconv.Atoi(s)
	if err != nil {
		return defaultVal
	}
	if val < minVal {
		return minVal
	}
	if maxVal >= 0 && val > maxVal {
		return maxVal
	}
	return val
}

// contactMatchesFilter checks if a contact matches the given lowercase filter string.
func contactMatchesFilter(info types.ContactInfo, lowerFilter string) bool {
	return strings.Contains(strings.ToLower(info.FullName), lowerFilter) ||
		strings.Contains(strings.ToLower(info.FirstName), lowerFilter) ||
		strings.Contains(strings.ToLower(info.PushName), lowerFilter) ||
		strings.Contains(strings.ToLower(info.BusinessName), lowerFilter)
}

// paginateSlice returns a slice of ContactEntry with offset and limit applied.
func paginateSlice(items []ContactEntry, offset, limit int) []ContactEntry {
	if offset >= len(items) {
		return []ContactEntry{}
	}
	end := offset + limit
	if end > len(items) {
		end = len(items)
	}
	return items[offset:end]
}

// parseBlocklistAction converts a string action to BlocklistChangeAction.
func parseBlocklistAction(action string) (events.BlocklistChangeAction, bool) {
	switch action {
	case "block":
		return events.BlocklistChangeActionBlock, true
	case "unblock":
		return events.BlocklistChangeActionUnblock, true
	default:
		return events.BlocklistChangeActionBlock, false
	}
}

// parseJIDField parses a JID string and writes an error response if invalid.
// Returns the parsed JID and true on success, or empty JID and false on failure.
func parseJIDField(w http.ResponseWriter, jidStr, fieldName string) (types.JID, bool) {
	jid, err := types.ParseJID(jidStr)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("Invalid %s format: %v", fieldName, err))
		return types.JID{}, false
	}
	return jid, true
}

// filterAndPaginateContacts filters contacts by name and applies pagination.
// Returns the filtered/paginated contacts and the total count before pagination.
func filterAndPaginateContacts(allContacts map[types.JID]types.ContactInfo, nameFilter string, offset, limit int) ([]ContactEntry, int) {
	// Pre-allocate with estimated capacity
	contacts := make([]ContactEntry, 0, len(allContacts))
	lowerFilter := strings.ToLower(nameFilter)

	for jid, info := range allContacts {
		if lowerFilter != "" && !contactMatchesFilter(info, lowerFilter) {
			continue
		}
		contacts = append(contacts, ContactEntry{
			JID:           jid.String(),
			FirstName:     info.FirstName,
			FullName:      info.FullName,
			PushName:      info.PushName,
			BusinessName:  info.BusinessName,
			RedactedPhone: info.RedactedPhone,
		})
	}

	sort.Slice(contacts, func(i, j int) bool {
		return contacts[i].JID < contacts[j].JID
	})

	total := len(contacts)
	contacts = paginateSlice(contacts, offset, limit)

	return contacts, total
}
