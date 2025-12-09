defmodule WhatsappMcp.BridgeTest do
  use ExUnit.Case, async: true

  alias WhatsappMcp.Bridge

  describe "health_check/1" do
    test "returns status map when connected with full info" do
      Req.Test.stub(:health_check_full, fn conn ->
        Req.Test.json(conn, %{connected: true, phone: "14155551234", name: "Alice"})
      end)

      assert {:ok, %{"connected" => true, "phone" => "14155551234", "name" => "Alice"}} =
               Bridge.health_check(plug: {Req.Test, :health_check_full})
    end

    test "returns status map when connected without name" do
      Req.Test.stub(:health_check_no_name, fn conn ->
        Req.Test.json(conn, %{connected: true, phone: "14155551234"})
      end)

      assert {:ok, %{"connected" => true, "phone" => "14155551234"}} =
               Bridge.health_check(plug: {Req.Test, :health_check_no_name})
    end

    test "returns connected false when not logged in" do
      Req.Test.stub(:health_check_not_logged_in, fn conn ->
        Req.Test.json(conn, %{connected: false})
      end)

      assert {:ok, %{"connected" => false}} =
               Bridge.health_check(plug: {Req.Test, :health_check_not_logged_in})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:health_check_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} = Bridge.health_check(plug: {Req.Test, :health_check_refused})
    end

    test "returns {:error, :bridge_not_running} on timeout" do
      Req.Test.stub(:health_check_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :bridge_not_running} = Bridge.health_check(plug: {Req.Test, :health_check_timeout})
    end

    test "returns {:ok, %{connected: false}} on non-200 status" do
      Req.Test.stub(:health_check_500, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"error": "Internal error"}))
      end)

      assert {:ok, %{"connected" => false}} =
               Bridge.health_check(plug: {Req.Test, :health_check_500})
    end
  end

  describe "send_message/3" do
    test "returns {:ok, message} on successful send" do
      Req.Test.stub(:send_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message sent to 12025551234"})
      end)

      assert {:ok, "Message sent to 12025551234"} =
               Bridge.send_message("12025551234", "Hello!", plug: {Req.Test, :send_success})
    end

    test "returns {:error, message} when bridge returns success: false" do
      Req.Test.stub(:send_failure, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Error parsing JID: invalid format"})
      end)

      assert {:error, "Error parsing JID: invalid format"} =
               Bridge.send_message("invalid", "Hi", plug: {Req.Test, :send_failure})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:send_conn_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.send_message("12025551234", "Hi", plug: {Req.Test, :send_conn_refused})
    end

    test "returns {:error, :timeout} on request timeout" do
      Req.Test.stub(:send_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.send_message("12025551234", "Hi", plug: {Req.Test, :send_timeout})
    end

    test "handles 400 error with message body" do
      Req.Test.stub(:send_400, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "Recipient is required"}))
      end)

      assert {:error, "Recipient is required"} =
               Bridge.send_message("", "Hi", plug: {Req.Test, :send_400})
    end

    test "handles 500 server error" do
      Req.Test.stub(:send_500, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"message": "Internal server error"}))
      end)

      assert {:error, "Internal server error"} =
               Bridge.send_message("12025551234", "Hi", plug: {Req.Test, :send_500})
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:send_verify_payload, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.send_message("12025551234", "Hello!", plug: {Req.Test, :send_verify_payload})

      assert_receive {:payload, %{"recipient" => "12025551234", "message" => "Hello!"}}
    end
  end

  describe "send_file/4" do
    test "returns {:error, :file_not_found} when file doesn't exist" do
      assert {:error, :file_not_found} =
               Bridge.send_file("12025551234", "/nonexistent/file.jpg")
    end

    test "returns {:error, :invalid_path} for relative paths" do
      assert {:error, :invalid_path} =
               Bridge.send_file("12025551234", "relative/path/file.jpg")
    end

    test "returns {:error, :invalid_path} for path traversal attempts" do
      assert {:error, :invalid_path} =
               Bridge.send_file("12025551234", "/tmp/../etc/passwd")
    end

    test "returns {:ok, message} on successful file send" do
      # Create a temporary test file
      tmp_path = Path.join(System.tmp_dir!(), "test_image.jpg")
      File.write!(tmp_path, "fake image data")

      Req.Test.stub(:send_file_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message sent to 12025551234"})
      end)

      assert {:ok, "Message sent to 12025551234"} =
               Bridge.send_file("12025551234", tmp_path, "Check this out", plug: {Req.Test, :send_file_success})

      File.rm!(tmp_path)
    end

    test "sends correct JSON payload with media_path" do
      test_pid = self()
      tmp_path = Path.join(System.tmp_dir!(), "test_doc.pdf")
      File.write!(tmp_path, "fake pdf data")

      Req.Test.stub(:send_file_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.send_file("12025551234", tmp_path, "My doc", plug: {Req.Test, :send_file_verify})

      assert_receive {:payload, payload}
      assert payload["recipient"] == "12025551234"
      assert payload["message"] == "My doc"
      assert payload["media_path"] == tmp_path

      File.rm!(tmp_path)
    end

    test "sends empty caption by default" do
      test_pid = self()
      tmp_path = Path.join(System.tmp_dir!(), "test_image2.jpg")
      File.write!(tmp_path, "fake image data")

      Req.Test.stub(:send_file_no_caption, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.send_file("12025551234", tmp_path, "", plug: {Req.Test, :send_file_no_caption})

      assert_receive {:payload, %{"message" => ""}}

      File.rm!(tmp_path)
    end

    test "returns {:error, :bridge_not_running} on closed connection" do
      tmp_path = Path.join(System.tmp_dir!(), "test_closed.jpg")
      File.write!(tmp_path, "fake image data")

      Req.Test.stub(:send_file_closed, fn conn ->
        Req.Test.transport_error(conn, :closed)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.send_file("12025551234", tmp_path, "", plug: {Req.Test, :send_file_closed})

      File.rm!(tmp_path)
    end

    test "handles 400 error response" do
      tmp_path = Path.join(System.tmp_dir!(), "test_400.jpg")
      File.write!(tmp_path, "fake image data")

      Req.Test.stub(:send_file_400, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "Invalid file format"}))
      end)

      assert {:error, "Invalid file format"} =
               Bridge.send_file("12025551234", tmp_path, "", plug: {Req.Test, :send_file_400})

      File.rm!(tmp_path)
    end
  end

  describe "send_audio/3" do
    test "returns {:error, :file_not_found} when file doesn't exist" do
      assert {:error, :file_not_found} =
               Bridge.send_audio("12025551234", "/nonexistent/voice.ogg")
    end

    test "returns {:error, :invalid_path} for relative paths" do
      assert {:error, :invalid_path} =
               Bridge.send_audio("12025551234", "relative/path/voice.ogg")
    end

    test "returns {:error, :invalid_path} for path traversal attempts" do
      assert {:error, :invalid_path} =
               Bridge.send_audio("12025551234", "/tmp/../etc/passwd.ogg")
    end

    test "returns {:ok, message} on successful audio send" do
      tmp_path = Path.join(System.tmp_dir!(), "test_voice.ogg")
      File.write!(tmp_path, "fake ogg data")

      Req.Test.stub(:send_audio_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message sent to 12025551234"})
      end)

      assert {:ok, "Message sent to 12025551234"} =
               Bridge.send_audio("12025551234", tmp_path, plug: {Req.Test, :send_audio_success})

      File.rm!(tmp_path)
    end

    test "sends correct JSON payload with empty message" do
      test_pid = self()
      tmp_path = Path.join(System.tmp_dir!(), "test_voice2.ogg")
      File.write!(tmp_path, "fake ogg data")

      Req.Test.stub(:send_audio_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.send_audio("12025551234", tmp_path, plug: {Req.Test, :send_audio_verify})

      assert_receive {:payload, payload}
      assert payload["recipient"] == "12025551234"
      assert payload["message"] == ""
      assert payload["media_path"] == tmp_path

      File.rm!(tmp_path)
    end

    test "returns {:error, message} when bridge returns format error" do
      tmp_path = Path.join(System.tmp_dir!(), "test_invalid.ogg")
      File.write!(tmp_path, "not valid ogg")

      Req.Test.stub(:send_audio_format_error, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Failed to analyze Ogg Opus file: invalid format"})
      end)

      assert {:error, "Failed to analyze Ogg Opus file: invalid format"} =
               Bridge.send_audio("12025551234", tmp_path, plug: {Req.Test, :send_audio_format_error})

      File.rm!(tmp_path)
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      tmp_path = Path.join(System.tmp_dir!(), "test_voice_refused.ogg")
      File.write!(tmp_path, "fake ogg data")

      Req.Test.stub(:send_audio_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.send_audio("12025551234", tmp_path, plug: {Req.Test, :send_audio_refused})

      File.rm!(tmp_path)
    end

    test "returns {:error, :timeout} on request timeout" do
      tmp_path = Path.join(System.tmp_dir!(), "test_voice_timeout.ogg")
      File.write!(tmp_path, "fake ogg data")

      Req.Test.stub(:send_audio_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.send_audio("12025551234", tmp_path, plug: {Req.Test, :send_audio_timeout})

      File.rm!(tmp_path)
    end
  end

  describe "download_media/3" do
    test "returns {:ok, map} with path, filename, media_type on success" do
      Req.Test.stub(:download_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully downloaded image media",
          filename: "photo.jpg",
          path: "/absolute/path/to/photo.jpg"
        })
      end)

      assert {:ok, result} =
               Bridge.download_media("MSG123", "12025551234@s.whatsapp.net", plug: {Req.Test, :download_success})

      assert result.path == "/absolute/path/to/photo.jpg"
      assert result.filename == "photo.jpg"
      assert result.media_type == "image"
    end

    test "extracts video media type from message" do
      Req.Test.stub(:download_video, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully downloaded video media",
          filename: "video.mp4",
          path: "/path/to/video.mp4"
        })
      end)

      assert {:ok, %{media_type: "video"}} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_video})
    end

    test "extracts audio media type from message" do
      Req.Test.stub(:download_audio, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully downloaded audio media",
          filename: "voice.ogg",
          path: "/path/to/voice.ogg"
        })
      end)

      assert {:ok, %{media_type: "audio"}} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_audio})
    end

    test "extracts document media type from message" do
      Req.Test.stub(:download_doc, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully downloaded document media",
          filename: "file.pdf",
          path: "/path/to/file.pdf"
        })
      end)

      assert {:ok, %{media_type: "document"}} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_doc})
    end

    test "returns {:error, message} when message has no media" do
      Req.Test.stub(:download_no_media, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          500,
          Jason.encode!(%{success: false, message: "Failed to download media: not a media message"})
        )
      end)

      assert {:error, "Failed to download media: not a media message"} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_no_media})
    end

    test "returns {:error, message} when media info incomplete" do
      Req.Test.stub(:download_incomplete, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          500,
          Jason.encode!(%{success: false, message: "Failed to download media: incomplete media information for download"})
        )
      end)

      assert {:error, "Failed to download media: incomplete media information for download"} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_incomplete})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:download_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_refused})
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:download_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Downloaded", filename: "f", path: "/p"})
      end)

      Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_verify})

      assert_receive {:payload, %{"message_id" => "MSG123", "chat_jid" => "chat@s.whatsapp.net"}}
    end

    test "returns {:error, :timeout} on request timeout" do
      Req.Test.stub(:download_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_timeout})
    end

    test "returns {:error, :bridge_not_running} on closed connection" do
      Req.Test.stub(:download_closed, fn conn ->
        Req.Test.transport_error(conn, :closed)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_closed})
    end

    test "extracts unknown media type when message has no recognizable type" do
      Req.Test.stub(:download_unknown_type, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully downloaded sticker media",
          filename: "sticker.webp",
          path: "/path/to/sticker.webp"
        })
      end)

      assert {:ok, %{media_type: "unknown"}} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_unknown_type})
    end

    test "handles nil message in success response" do
      Req.Test.stub(:download_nil_message, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: nil,
          filename: "file.bin",
          path: "/path/to/file.bin"
        })
      end)

      assert {:ok, %{media_type: "unknown"}} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_nil_message})
    end

    test "handles 400 error response with string body" do
      Req.Test.stub(:download_400_string, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(400, "Bad Request: invalid message_id")
      end)

      assert {:error, "Bad Request: invalid message_id"} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_400_string})
    end

    test "handles 500 error response with no message field" do
      Req.Test.stub(:download_500_no_message, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"error": "Internal error"}))
      end)

      assert {:error, "Download failed"} =
               Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_500_no_message})
    end

    test "handles generic error from Req" do
      Req.Test.stub(:download_generic_error, fn conn ->
        # Simulate an unexpected error type
        Req.Test.transport_error(conn, :nxdomain)
      end)

      result = Bridge.download_media("MSG123", "chat@s.whatsapp.net", plug: {Req.Test, :download_generic_error})

      assert {:error, error_msg} = result
      assert is_binary(error_msg)
    end
  end

  describe "error handling edge cases" do
    test "send_message handles generic error from Req" do
      Req.Test.stub(:send_generic_error, fn conn ->
        Req.Test.transport_error(conn, :nxdomain)
      end)

      result = Bridge.send_message("12025551234", "test", plug: {Req.Test, :send_generic_error})

      assert {:error, error_msg} = result
      assert is_binary(error_msg)
    end

    test "send_message handles closed connection" do
      Req.Test.stub(:send_closed, fn conn ->
        Req.Test.transport_error(conn, :closed)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.send_message("12025551234", "test", plug: {Req.Test, :send_closed})
    end

    test "health_check handles closed connection" do
      Req.Test.stub(:health_closed, fn conn ->
        Req.Test.transport_error(conn, :closed)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.health_check(plug: {Req.Test, :health_closed})
    end

    test "health_check handles generic error" do
      Req.Test.stub(:health_generic, fn conn ->
        Req.Test.transport_error(conn, :nxdomain)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.health_check(plug: {Req.Test, :health_generic})
    end
  end

  describe "health_check uses GET request" do
    test "uses GET method for health endpoint" do
      test_pid = self()

      Req.Test.stub(:health_method_check, fn conn ->
        send(test_pid, {:method, conn.method})
        Req.Test.json(conn, %{connected: true, phone: "123"})
      end)

      Bridge.health_check(plug: {Req.Test, :health_method_check})

      assert_receive {:method, "GET"}
    end
  end

  describe "resolve_lid/2" do
    test "returns {:ok, map} with phone and name on success" do
      Req.Test.stub(:resolve_lid_success, fn conn ->
        Req.Test.json(conn, %{success: true, phone: "14155552345", name: "John Doe"})
      end)

      assert {:ok, %{phone: "14155552345", name: "John Doe"}} =
               Bridge.resolve_lid("144555781402794@lid", plug: {Req.Test, :resolve_lid_success})
    end

    test "returns {:ok, map} with phone only when name is nil" do
      Req.Test.stub(:resolve_lid_no_name, fn conn ->
        Req.Test.json(conn, %{success: true, phone: "14155552345", name: nil})
      end)

      assert {:ok, %{phone: "14155552345", name: nil}} =
               Bridge.resolve_lid("144555781402794@lid", plug: {Req.Test, :resolve_lid_no_name})
    end

    test "returns {:error, message} when resolution fails" do
      Req.Test.stub(:resolve_lid_not_found, fn conn ->
        Req.Test.json(conn, %{success: false, message: "No user info found for this LID"})
      end)

      assert {:error, "No user info found for this LID"} =
               Bridge.resolve_lid("invalid@lid", plug: {Req.Test, :resolve_lid_not_found})
    end

    test "returns {:error, message} on invalid JID format" do
      Req.Test.stub(:resolve_lid_invalid, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{success: false, message: "Invalid JID format: xyz"}))
      end)

      assert {:error, "Invalid JID format: xyz"} =
               Bridge.resolve_lid("xyz", plug: {Req.Test, :resolve_lid_invalid})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:resolve_lid_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.resolve_lid("144555781402794@lid", plug: {Req.Test, :resolve_lid_refused})
    end

    test "returns {:error, :timeout} on request timeout" do
      Req.Test.stub(:resolve_lid_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.resolve_lid("144555781402794@lid", plug: {Req.Test, :resolve_lid_timeout})
    end

    test "returns {:error, :bridge_not_running} on closed connection" do
      Req.Test.stub(:resolve_lid_closed, fn conn ->
        Req.Test.transport_error(conn, :closed)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.resolve_lid("144555781402794@lid", plug: {Req.Test, :resolve_lid_closed})
    end

    test "handles 500 error response" do
      Req.Test.stub(:resolve_lid_500, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{success: false, message: "Internal server error"}))
      end)

      assert {:error, "Internal server error"} =
               Bridge.resolve_lid("144555781402794@lid", plug: {Req.Test, :resolve_lid_500})
    end

    test "handles generic error from Req" do
      Req.Test.stub(:resolve_lid_generic_error, fn conn ->
        Req.Test.transport_error(conn, :nxdomain)
      end)

      result = Bridge.resolve_lid("144555781402794@lid", plug: {Req.Test, :resolve_lid_generic_error})

      assert {:error, error_msg} = result
      assert is_binary(error_msg)
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:resolve_lid_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, phone: "123", name: "Test"})
      end)

      Bridge.resolve_lid("144555781402794@lid", plug: {Req.Test, :resolve_lid_verify})

      assert_receive {:payload, %{"lid" => "144555781402794@lid"}}
    end

    test "uses POST method for resolve-lid endpoint" do
      test_pid = self()

      Req.Test.stub(:resolve_lid_method_check, fn conn ->
        send(test_pid, {:method, conn.method})
        Req.Test.json(conn, %{success: true, phone: "123"})
      end)

      Bridge.resolve_lid("144555781402794@lid", plug: {Req.Test, :resolve_lid_method_check})

      assert_receive {:method, "POST"}
    end
  end

  describe "send_typing/3" do
    test "returns {:ok, message} on successful typing start" do
      Req.Test.stub(:typing_start_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Typing indicator started for 12025551234"})
      end)

      assert {:ok, "Typing indicator started for 12025551234"} =
               Bridge.send_typing("12025551234", true, plug: {Req.Test, :typing_start_success})
    end

    test "returns {:ok, message} on successful typing stop" do
      Req.Test.stub(:typing_stop_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Typing indicator stopped for 12025551234"})
      end)

      assert {:ok, "Typing indicator stopped for 12025551234"} =
               Bridge.send_typing("12025551234", false, plug: {Req.Test, :typing_stop_success})
    end

    test "returns {:error, message} on invalid JID" do
      Req.Test.stub(:typing_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid JID format: xyz"})
      end)

      assert {:error, "Invalid JID format: xyz"} =
               Bridge.send_typing("xyz", true, plug: {Req.Test, :typing_invalid_jid})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:typing_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.send_typing("12025551234", true, plug: {Req.Test, :typing_refused})
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:typing_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.send_typing("12025551234", true, plug: {Req.Test, :typing_verify})

      assert_receive {:payload, %{"recipient" => "12025551234", "composing" => true}}
    end
  end

  describe "mark_read/3" do
    test "returns {:ok, message} on successful mark read" do
      Req.Test.stub(:mark_read_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Marked 2 message(s) as read in 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, "Marked 2 message(s) as read in 12025551234@s.whatsapp.net"} =
               Bridge.mark_read("12025551234@s.whatsapp.net", ["MSG1", "MSG2"], plug: {Req.Test, :mark_read_success})
    end

    test "returns {:error, message} on invalid chat JID" do
      Req.Test.stub(:mark_read_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid chat JID format: xyz"})
      end)

      assert {:error, "Invalid chat JID format: xyz"} =
               Bridge.mark_read("xyz", ["MSG1"], plug: {Req.Test, :mark_read_invalid_jid})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:mark_read_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.mark_read("12025551234@s.whatsapp.net", ["MSG1"], plug: {Req.Test, :mark_read_refused})
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:mark_read_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Marked"})
      end)

      Bridge.mark_read("12025551234@s.whatsapp.net", ["MSG1", "MSG2"], plug: {Req.Test, :mark_read_verify})

      assert_receive {:payload, %{"chat_jid" => "12025551234@s.whatsapp.net", "message_ids" => ["MSG1", "MSG2"]}}
    end
  end

  describe "send_reaction/5" do
    test "returns {:ok, message} on successful reaction add" do
      Req.Test.stub(:reaction_add_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Reaction added for message ABC123"})
      end)

      assert {:ok, "Reaction added for message ABC123"} =
               Bridge.send_reaction(
                 "12025551234@s.whatsapp.net",
                 "ABC123",
                 "12025551234@s.whatsapp.net",
                 "👍",
                 plug: {Req.Test, :reaction_add_success}
               )
    end

    test "returns {:ok, message} on successful reaction remove" do
      Req.Test.stub(:reaction_remove_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Reaction removed for message ABC123"})
      end)

      assert {:ok, "Reaction removed for message ABC123"} =
               Bridge.send_reaction(
                 "12025551234@s.whatsapp.net",
                 "ABC123",
                 "12025551234@s.whatsapp.net",
                 "",
                 plug: {Req.Test, :reaction_remove_success}
               )
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:reaction_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.send_reaction(
                 "12025551234@s.whatsapp.net",
                 "ABC123",
                 "12025551234@s.whatsapp.net",
                 "👍",
                 plug: {Req.Test, :reaction_refused}
               )
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:reaction_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.send_reaction(
        "12025551234@s.whatsapp.net",
        "ABC123",
        "14155551234@s.whatsapp.net",
        "👍",
        plug: {Req.Test, :reaction_verify}
      )

      assert_receive {:payload,
                      %{
                        "chat_jid" => "12025551234@s.whatsapp.net",
                        "message_id" => "ABC123",
                        "sender" => "14155551234@s.whatsapp.net",
                        "emoji" => "👍"
                      }}
    end
  end

  describe "delete_message/4" do
    test "returns {:ok, message} on successful delete" do
      Req.Test.stub(:delete_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message ABC123 deleted from 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, "Message ABC123 deleted from 12025551234@s.whatsapp.net"} =
               Bridge.delete_message(
                 "12025551234@s.whatsapp.net",
                 "ABC123",
                 "14155551234@s.whatsapp.net",
                 plug: {Req.Test, :delete_success}
               )
    end

    test "returns {:error, message} on invalid chat JID" do
      Req.Test.stub(:delete_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid chat JID format: xyz"})
      end)

      assert {:error, "Invalid chat JID format: xyz"} =
               Bridge.delete_message("xyz", "ABC123", "14155551234@s.whatsapp.net", plug: {Req.Test, :delete_invalid_jid})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:delete_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.delete_message(
                 "12025551234@s.whatsapp.net",
                 "ABC123",
                 "14155551234@s.whatsapp.net",
                 plug: {Req.Test, :delete_refused}
               )
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:delete_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Deleted"})
      end)

      Bridge.delete_message(
        "12025551234@s.whatsapp.net",
        "ABC123",
        "14155551234@s.whatsapp.net",
        plug: {Req.Test, :delete_verify}
      )

      assert_receive {:payload,
                      %{
                        "chat_jid" => "12025551234@s.whatsapp.net",
                        "message_id" => "ABC123",
                        "sender" => "14155551234@s.whatsapp.net"
                      }}
    end
  end

  describe "reply_to_message/6" do
    test "returns {:ok, message} on successful reply" do
      Req.Test.stub(:reply_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Reply sent to 12025551234"})
      end)

      assert {:ok, "Reply sent to 12025551234"} =
               Bridge.reply_to_message(
                 "12025551234",
                 "Thanks!",
                 "ABC123",
                 "12025551234@s.whatsapp.net",
                 "14155551234@s.whatsapp.net",
                 plug: {Req.Test, :reply_success}
               )
    end

    test "returns {:error, message} on invalid recipient JID" do
      Req.Test.stub(:reply_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid recipient JID format: xyz"})
      end)

      assert {:error, "Invalid recipient JID format: xyz"} =
               Bridge.reply_to_message(
                 "xyz",
                 "Thanks!",
                 "ABC123",
                 "12025551234@s.whatsapp.net",
                 "14155551234@s.whatsapp.net",
                 plug: {Req.Test, :reply_invalid_jid}
               )
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:reply_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.reply_to_message(
                 "12025551234",
                 "Thanks!",
                 "ABC123",
                 "12025551234@s.whatsapp.net",
                 "14155551234@s.whatsapp.net",
                 plug: {Req.Test, :reply_refused}
               )
    end

    test "sends correct JSON payload with quoted_sender" do
      test_pid = self()

      Req.Test.stub(:reply_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.reply_to_message(
        "12025551234",
        "Thanks for the info!",
        "ABC123",
        "12025551234@s.whatsapp.net",
        "14155551234@s.whatsapp.net",
        plug: {Req.Test, :reply_verify}
      )

      assert_receive {:payload,
                      %{
                        "recipient" => "12025551234",
                        "message" => "Thanks for the info!",
                        "quoted_message_id" => "ABC123",
                        "quoted_chat_jid" => "12025551234@s.whatsapp.net",
                        "quoted_sender" => "14155551234@s.whatsapp.net"
                      }}
    end
  end

  describe "send_location/4" do
    test "returns {:ok, message} on successful location send" do
      Req.Test.stub(:location_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Location sent to 12025551234"})
      end)

      assert {:ok, "Location sent to 12025551234"} =
               Bridge.send_location("12025551234", 48.8584, 2.2945, plug: {Req.Test, :location_success})
    end

    test "sends location with name and address" do
      Req.Test.stub(:location_named, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Location sent to 12025551234"})
      end)

      assert {:ok, "Location sent to 12025551234"} =
               Bridge.send_location(
                 "12025551234",
                 48.8584,
                 2.2945,
                 name: "Eiffel Tower",
                 address: "Champ de Mars, Paris",
                 plug: {Req.Test, :location_named}
               )
    end

    test "returns {:error, message} on invalid recipient JID" do
      Req.Test.stub(:location_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid recipient JID format: xyz"})
      end)

      assert {:error, "Invalid recipient JID format: xyz"} =
               Bridge.send_location("xyz", 48.8584, 2.2945, plug: {Req.Test, :location_invalid_jid})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:location_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.send_location("12025551234", 48.8584, 2.2945, plug: {Req.Test, :location_refused})
    end

    test "sends correct JSON payload without name/address" do
      test_pid = self()

      Req.Test.stub(:location_verify_basic, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.send_location("12025551234", 48.8584, 2.2945, plug: {Req.Test, :location_verify_basic})

      assert_receive {:payload, payload}
      assert payload["recipient"] == "12025551234"
      assert payload["latitude"] == 48.8584
      assert payload["longitude"] == 2.2945
      refute Map.has_key?(payload, "name")
      refute Map.has_key?(payload, "address")
    end

    test "sends correct JSON payload with name and address" do
      test_pid = self()

      Req.Test.stub(:location_verify_full, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.send_location(
        "12025551234",
        48.8584,
        2.2945,
        name: "Eiffel Tower",
        address: "Champ de Mars",
        plug: {Req.Test, :location_verify_full}
      )

      assert_receive {:payload,
                      %{
                        "recipient" => "12025551234",
                        "latitude" => 48.8584,
                        "longitude" => 2.2945,
                        "name" => "Eiffel Tower",
                        "address" => "Champ de Mars"
                      }}
    end
  end

  describe "edit_message/4" do
    test "returns {:ok, message} on successful edit" do
      Req.Test.stub(:edit_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Message ABC123 edited in 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, "Message ABC123 edited in 12025551234@s.whatsapp.net"} =
               Bridge.edit_message(
                 "12025551234@s.whatsapp.net",
                 "ABC123",
                 "Fixed typo!",
                 plug: {Req.Test, :edit_success}
               )
    end

    test "returns {:error, message} on invalid chat JID" do
      Req.Test.stub(:edit_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid chat JID format: xyz"})
      end)

      assert {:error, "Invalid chat JID format: xyz"} =
               Bridge.edit_message("xyz", "ABC123", "New content", plug: {Req.Test, :edit_invalid_jid})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:edit_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.edit_message(
                 "12025551234@s.whatsapp.net",
                 "ABC123",
                 "New content",
                 plug: {Req.Test, :edit_refused}
               )
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:edit_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Edited"})
      end)

      Bridge.edit_message(
        "12025551234@s.whatsapp.net",
        "ABC123",
        "Fixed the typo!",
        plug: {Req.Test, :edit_verify}
      )

      assert_receive {:payload,
                      %{
                        "chat_jid" => "12025551234@s.whatsapp.net",
                        "message_id" => "ABC123",
                        "new_content" => "Fixed the typo!"
                      }}
    end
  end

  describe "set_presence/2" do
    test "returns {:ok, message} on successful presence set to available" do
      Req.Test.stub(:presence_available, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Presence set to available"})
      end)

      assert {:ok, "Presence set to available"} =
               Bridge.set_presence(true, plug: {Req.Test, :presence_available})
    end

    test "returns {:ok, message} on successful presence set to unavailable" do
      Req.Test.stub(:presence_unavailable, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Presence set to unavailable"})
      end)

      assert {:ok, "Presence set to unavailable"} =
               Bridge.set_presence(false, plug: {Req.Test, :presence_unavailable})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:presence_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.set_presence(true, plug: {Req.Test, :presence_refused})
    end

    test "sends correct JSON payload for available" do
      test_pid = self()

      Req.Test.stub(:presence_verify_available, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Set"})
      end)

      Bridge.set_presence(true, plug: {Req.Test, :presence_verify_available})

      assert_receive {:payload, %{"available" => true}}
    end

    test "sends correct JSON payload for unavailable" do
      test_pid = self()

      Req.Test.stub(:presence_verify_unavailable, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Set"})
      end)

      Bridge.set_presence(false, plug: {Req.Test, :presence_verify_unavailable})

      assert_receive {:payload, %{"available" => false}}
    end
  end

  describe "subscribe_presence/2" do
    test "returns {:ok, message} on successful subscription" do
      Req.Test.stub(:subscribe_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Subscribed to presence updates for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, "Subscribed to presence updates for 12025551234@s.whatsapp.net"} =
               Bridge.subscribe_presence("12025551234@s.whatsapp.net", plug: {Req.Test, :subscribe_success})
    end

    test "returns {:error, message} on invalid JID" do
      Req.Test.stub(:subscribe_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid JID format: xyz"})
      end)

      assert {:error, "Invalid JID format: xyz"} =
               Bridge.subscribe_presence("xyz", plug: {Req.Test, :subscribe_invalid_jid})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:subscribe_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.subscribe_presence("12025551234@s.whatsapp.net", plug: {Req.Test, :subscribe_refused})
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:subscribe_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Subscribed"})
      end)

      Bridge.subscribe_presence("12025551234@s.whatsapp.net", plug: {Req.Test, :subscribe_verify})

      assert_receive {:payload, %{"jid" => "12025551234@s.whatsapp.net"}}
    end
  end

  describe "set_disappearing_timer/3" do
    test "returns {:ok, message} on successful timer set to 24h" do
      Req.Test.stub(:disappearing_24h, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Disappearing messages set to 24h for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, "Disappearing messages set to 24h for 12025551234@s.whatsapp.net"} =
               Bridge.set_disappearing_timer("12025551234@s.whatsapp.net", "24h", plug: {Req.Test, :disappearing_24h})
    end

    test "returns {:ok, message} on successful timer set to off" do
      Req.Test.stub(:disappearing_off, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Disappearing messages set to off for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, "Disappearing messages set to off for 12025551234@s.whatsapp.net"} =
               Bridge.set_disappearing_timer("12025551234@s.whatsapp.net", "off", plug: {Req.Test, :disappearing_off})
    end

    test "returns {:ok, message} on successful timer set to 7d" do
      Req.Test.stub(:disappearing_7d, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Disappearing messages set to 7d for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, "Disappearing messages set to 7d for 12025551234@s.whatsapp.net"} =
               Bridge.set_disappearing_timer("12025551234@s.whatsapp.net", "7d", plug: {Req.Test, :disappearing_7d})
    end

    test "returns {:ok, message} on successful timer set to 90d" do
      Req.Test.stub(:disappearing_90d, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Disappearing messages set to 90d for 12025551234@s.whatsapp.net"})
      end)

      assert {:ok, "Disappearing messages set to 90d for 12025551234@s.whatsapp.net"} =
               Bridge.set_disappearing_timer("12025551234@s.whatsapp.net", "90d", plug: {Req.Test, :disappearing_90d})
    end

    test "returns {:error, message} on invalid chat JID" do
      Req.Test.stub(:disappearing_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid chat JID format: xyz"})
      end)

      assert {:error, "Invalid chat JID format: xyz"} =
               Bridge.set_disappearing_timer("xyz", "24h", plug: {Req.Test, :disappearing_invalid_jid})
    end

    test "returns {:error, message} on invalid timer value" do
      Req.Test.stub(:disappearing_invalid_timer, fn conn ->
        Req.Test.json(conn, %{success: false, message: "timer must be one of: off, 24h, 7d, 90d"})
      end)

      assert {:error, "timer must be one of: off, 24h, 7d, 90d"} =
               Bridge.set_disappearing_timer("12025551234@s.whatsapp.net", "1h",
                 plug: {Req.Test, :disappearing_invalid_timer}
               )
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:disappearing_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.set_disappearing_timer("12025551234@s.whatsapp.net", "24h", plug: {Req.Test, :disappearing_refused})
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:disappearing_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Set"})
      end)

      Bridge.set_disappearing_timer("12025551234@s.whatsapp.net", "7d", plug: {Req.Test, :disappearing_verify})

      assert_receive {:payload, %{"chat_jid" => "12025551234@s.whatsapp.net", "timer" => "7d"}}
    end
  end

  describe "check_whatsapp_registration/2" do
    test "returns {:ok, results} on successful check" do
      Req.Test.stub(:check_registration_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          results: [
            %{phone: "12025551234", is_on_whatsapp: true, jid: "12025551234@s.whatsapp.net"},
            %{phone: "44123456789", is_on_whatsapp: false, jid: ""}
          ]
        })
      end)

      assert {:ok, results} =
               Bridge.check_whatsapp_registration(["12025551234", "44123456789"],
                 plug: {Req.Test, :check_registration_success}
               )

      assert length(results) == 2
      assert Enum.at(results, 0).phone == "12025551234"
      assert Enum.at(results, 0).is_on_whatsapp == true
      assert Enum.at(results, 0).jid == "12025551234@s.whatsapp.net"
      assert Enum.at(results, 1).phone == "44123456789"
      assert Enum.at(results, 1).is_on_whatsapp == false
      assert Enum.at(results, 1).jid == nil
    end

    test "returns {:error, message} when bridge returns error" do
      Req.Test.stub(:check_registration_empty, fn conn ->
        Req.Test.json(conn, %{success: false, message: "phones array is required and cannot be empty"})
      end)

      assert {:error, "phones array is required and cannot be empty"} =
               Bridge.check_whatsapp_registration([], plug: {Req.Test, :check_registration_empty})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:check_registration_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.check_whatsapp_registration(["12025551234"], plug: {Req.Test, :check_registration_refused})
    end

    test "returns {:error, :timeout} on request timeout" do
      Req.Test.stub(:check_registration_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.check_whatsapp_registration(["12025551234"], plug: {Req.Test, :check_registration_timeout})
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:check_registration_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, results: []})
      end)

      Bridge.check_whatsapp_registration(["12025551234", "44123456789"],
        plug: {Req.Test, :check_registration_verify}
      )

      assert_receive {:payload, %{"phones" => ["12025551234", "44123456789"]}}
    end
  end

  describe "get_profile_picture/2" do
    test "returns {:ok, %{url, id}} on success" do
      Req.Test.stub(:profile_pic_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          url: "https://pps.whatsapp.net/v/t61.24694-24/abc123.jpg",
          id: "1234567890"
        })
      end)

      assert {:ok, %{url: url, id: id}} =
               Bridge.get_profile_picture("12025551234@s.whatsapp.net", plug: {Req.Test, :profile_pic_success})

      assert url == "https://pps.whatsapp.net/v/t61.24694-24/abc123.jpg"
      assert id == "1234567890"
    end

    test "returns {:error, message} when no profile picture" do
      Req.Test.stub(:profile_pic_not_found, fn conn ->
        Req.Test.json(conn, %{success: false, message: "No profile picture set for this contact"})
      end)

      assert {:error, "No profile picture set for this contact"} =
               Bridge.get_profile_picture("12025551234@s.whatsapp.net", plug: {Req.Test, :profile_pic_not_found})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:profile_pic_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.get_profile_picture("12025551234@s.whatsapp.net", plug: {Req.Test, :profile_pic_refused})
    end

    test "returns {:error, :timeout} on request timeout" do
      Req.Test.stub(:profile_pic_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.get_profile_picture("12025551234@s.whatsapp.net", plug: {Req.Test, :profile_pic_timeout})
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:profile_pic_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, url: "https://test", id: "123"})
      end)

      Bridge.get_profile_picture("12025551234@s.whatsapp.net", plug: {Req.Test, :profile_pic_verify})

      assert_receive {:payload, %{"jid" => "12025551234@s.whatsapp.net"}}
    end
  end

  describe "get_blocklist/1" do
    test "returns {:ok, blocklist} on success" do
      Req.Test.stub(:blocklist_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          blocklist: ["12025551234@s.whatsapp.net", "44123456789@s.whatsapp.net"]
        })
      end)

      assert {:ok, blocklist} = Bridge.get_blocklist(plug: {Req.Test, :blocklist_success})
      assert blocklist == ["12025551234@s.whatsapp.net", "44123456789@s.whatsapp.net"]
    end

    test "returns {:ok, []} when blocklist is empty" do
      Req.Test.stub(:blocklist_empty, fn conn ->
        Req.Test.json(conn, %{success: true, blocklist: []})
      end)

      assert {:ok, []} = Bridge.get_blocklist(plug: {Req.Test, :blocklist_empty})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:blocklist_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} = Bridge.get_blocklist(plug: {Req.Test, :blocklist_refused})
    end

    test "returns {:error, :timeout} on request timeout" do
      Req.Test.stub(:blocklist_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} = Bridge.get_blocklist(plug: {Req.Test, :blocklist_timeout})
    end

    test "uses GET method" do
      test_pid = self()

      Req.Test.stub(:blocklist_method_check, fn conn ->
        send(test_pid, {:method, conn.method})
        Req.Test.json(conn, %{success: true, blocklist: []})
      end)

      Bridge.get_blocklist(plug: {Req.Test, :blocklist_method_check})

      assert_receive {:method, "GET"}
    end
  end

  describe "update_blocklist/3" do
    test "returns {:ok, message} on successful block" do
      Req.Test.stub(:block_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Contact 12025551234@s.whatsapp.net blocked"})
      end)

      assert {:ok, "Contact 12025551234@s.whatsapp.net blocked"} =
               Bridge.update_blocklist("12025551234@s.whatsapp.net", "block", plug: {Req.Test, :block_success})
    end

    test "returns {:ok, message} on successful unblock" do
      Req.Test.stub(:unblock_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Contact 12025551234@s.whatsapp.net unblocked"})
      end)

      assert {:ok, "Contact 12025551234@s.whatsapp.net unblocked"} =
               Bridge.update_blocklist("12025551234@s.whatsapp.net", "unblock", plug: {Req.Test, :unblock_success})
    end

    test "returns {:error, message} on invalid action" do
      Req.Test.stub(:block_invalid_action, fn conn ->
        Req.Test.json(conn, %{success: false, message: "action must be 'block' or 'unblock'"})
      end)

      assert {:error, "action must be 'block' or 'unblock'"} =
               Bridge.update_blocklist("12025551234@s.whatsapp.net", "invalid", plug: {Req.Test, :block_invalid_action})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:block_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.update_blocklist("12025551234@s.whatsapp.net", "block", plug: {Req.Test, :block_refused})
    end

    test "sends correct JSON payload for block" do
      test_pid = self()

      Req.Test.stub(:block_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Blocked"})
      end)

      Bridge.update_blocklist("12025551234@s.whatsapp.net", "block", plug: {Req.Test, :block_verify})

      assert_receive {:payload, %{"jid" => "12025551234@s.whatsapp.net", "action" => "block"}}
    end

    test "sends correct JSON payload for unblock" do
      test_pid = self()

      Req.Test.stub(:unblock_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Unblocked"})
      end)

      Bridge.update_blocklist("12025551234@s.whatsapp.net", "unblock", plug: {Req.Test, :unblock_verify})

      assert_receive {:payload, %{"jid" => "12025551234@s.whatsapp.net", "action" => "unblock"}}
    end
  end

  describe "create_poll/5" do
    test "returns {:ok, message} on successful single-choice poll" do
      Req.Test.stub(:poll_single_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Poll sent to 12025551234 (single-choice with 3 options)"})
      end)

      assert {:ok, "Poll sent to 12025551234 (single-choice with 3 options)"} =
               Bridge.create_poll(
                 "12025551234",
                 "What's for lunch?",
                 ["Pizza", "Sushi", "Salad"],
                 1,
                 plug: {Req.Test, :poll_single_success}
               )
    end

    test "returns {:ok, message} on successful multi-choice poll" do
      Req.Test.stub(:poll_multi_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Poll sent to 12025551234 (multi-choice (up to 3) with 4 options)"})
      end)

      assert {:ok, "Poll sent to 12025551234 (multi-choice (up to 3) with 4 options)"} =
               Bridge.create_poll(
                 "12025551234",
                 "Select toppings",
                 ["Cheese", "Pepperoni", "Mushrooms", "Olives"],
                 3,
                 plug: {Req.Test, :poll_multi_success}
               )
    end

    test "returns {:error, message} on invalid recipient JID" do
      Req.Test.stub(:poll_invalid_jid, fn conn ->
        Req.Test.json(conn, %{success: false, message: "Invalid recipient JID format: xyz"})
      end)

      assert {:error, "Invalid recipient JID format: xyz"} =
               Bridge.create_poll(
                 "xyz",
                 "Question?",
                 ["A", "B"],
                 1,
                 plug: {Req.Test, :poll_invalid_jid}
               )
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:poll_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.create_poll(
                 "12025551234",
                 "Question?",
                 ["A", "B"],
                 1,
                 plug: {Req.Test, :poll_refused}
               )
    end

    test "returns {:error, :timeout} on request timeout" do
      Req.Test.stub(:poll_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.create_poll(
                 "12025551234",
                 "Question?",
                 ["A", "B"],
                 1,
                 plug: {Req.Test, :poll_timeout}
               )
    end

    test "sends correct JSON payload for single-choice poll" do
      test_pid = self()

      Req.Test.stub(:poll_verify_single, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.create_poll(
        "12025551234",
        "What's your favorite?",
        ["Red", "Blue", "Green"],
        1,
        plug: {Req.Test, :poll_verify_single}
      )

      assert_receive {:payload,
                      %{
                        "recipient" => "12025551234",
                        "question" => "What's your favorite?",
                        "options" => ["Red", "Blue", "Green"],
                        "max_selections" => 1
                      }}
    end

    test "sends correct JSON payload for multi-choice poll" do
      test_pid = self()

      Req.Test.stub(:poll_verify_multi, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Sent"})
      end)

      Bridge.create_poll(
        "12025551234@s.whatsapp.net",
        "Pick up to 2",
        ["Option A", "Option B", "Option C"],
        2,
        plug: {Req.Test, :poll_verify_multi}
      )

      assert_receive {:payload,
                      %{
                        "recipient" => "12025551234@s.whatsapp.net",
                        "question" => "Pick up to 2",
                        "options" => ["Option A", "Option B", "Option C"],
                        "max_selections" => 2
                      }}
    end

    test "handles 400 error with message body" do
      Req.Test.stub(:poll_400, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "at least 2 options are required"}))
      end)

      assert {:error, "at least 2 options are required"} =
               Bridge.create_poll(
                 "12025551234",
                 "Question?",
                 ["Only one"],
                 1,
                 plug: {Req.Test, :poll_400}
               )
    end

    test "handles 500 server error" do
      Req.Test.stub(:poll_500, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"message": "Failed to send poll: internal error"}))
      end)

      assert {:error, "Failed to send poll: internal error"} =
               Bridge.create_poll(
                 "12025551234",
                 "Question?",
                 ["A", "B"],
                 1,
                 plug: {Req.Test, :poll_500}
               )
    end
  end

  describe "list_groups/1" do
    test "returns {:ok, groups} on success with groups" do
      Req.Test.stub(:list_groups_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          groups: [
            %{
              jid: "120363123456789012@g.us",
              name: "Family Group",
              topic: "Stay connected!",
              participant_count: 5,
              is_announce: false,
              is_locked: false
            },
            %{
              jid: "120363987654321098@g.us",
              name: "Work Team",
              topic: "",
              participant_count: 10,
              is_announce: true,
              is_locked: true
            }
          ]
        })
      end)

      assert {:ok, groups} = Bridge.list_groups(plug: {Req.Test, :list_groups_success})
      assert length(groups) == 2

      assert Enum.at(groups, 0)["jid"] == "120363123456789012@g.us"
      assert Enum.at(groups, 0)["name"] == "Family Group"
      assert Enum.at(groups, 0)["topic"] == "Stay connected!"
      assert Enum.at(groups, 0)["participant_count"] == 5
      assert Enum.at(groups, 0)["is_announce"] == false

      assert Enum.at(groups, 1)["jid"] == "120363987654321098@g.us"
      assert Enum.at(groups, 1)["is_announce"] == true
    end

    test "returns {:ok, []} when no groups joined" do
      Req.Test.stub(:list_groups_empty, fn conn ->
        Req.Test.json(conn, %{success: true, groups: []})
      end)

      assert {:ok, []} = Bridge.list_groups(plug: {Req.Test, :list_groups_empty})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:list_groups_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} = Bridge.list_groups(plug: {Req.Test, :list_groups_refused})
    end

    test "returns {:error, :timeout} on request timeout" do
      Req.Test.stub(:list_groups_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} = Bridge.list_groups(plug: {Req.Test, :list_groups_timeout})
    end

    test "uses GET method" do
      test_pid = self()

      Req.Test.stub(:list_groups_method_check, fn conn ->
        send(test_pid, {:method, conn.method})
        Req.Test.json(conn, %{success: true, groups: []})
      end)

      Bridge.list_groups(plug: {Req.Test, :list_groups_method_check})

      assert_receive {:method, "GET"}
    end
  end

  describe "get_group_info/2" do
    test "returns {:ok, group} on success with full details" do
      Req.Test.stub(:group_info_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          group: %{
            jid: "120363123456789012@g.us",
            name: "Family Group",
            topic: "Stay connected!",
            topic_set_by: "12025551234@s.whatsapp.net",
            topic_set_at: "2025-01-15T10:30:00Z",
            owner_jid: "12025551234@s.whatsapp.net",
            created_at: "2024-06-01T08:00:00Z",
            participant_count: 3,
            participants: [
              %{jid: "12025551234@s.whatsapp.net", is_admin: true, is_super_admin: true},
              %{jid: "12025555678@s.whatsapp.net", is_admin: true, is_super_admin: false},
              %{jid: "12025559999@s.whatsapp.net", is_admin: false, is_super_admin: false}
            ],
            is_announce: false,
            is_locked: false
          }
        })
      end)

      assert {:ok, group} = Bridge.get_group_info("120363123456789012@g.us", plug: {Req.Test, :group_info_success})

      assert group["jid"] == "120363123456789012@g.us"
      assert group["name"] == "Family Group"
      assert group["topic"] == "Stay connected!"
      assert group["participant_count"] == 3
      assert length(group["participants"]) == 3

      # Check admin roles
      admin = Enum.find(group["participants"], &(&1["is_super_admin"] == true))
      assert admin["jid"] == "12025551234@s.whatsapp.net"
      assert admin["is_admin"] == true
    end

    test "returns {:error, message} for non-group JID" do
      error_msg = "JID is not a group (must end with @g.us)"

      Req.Test.stub(:group_info_not_group, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{message: error_msg}))
      end)

      assert {:error, ^error_msg} =
               Bridge.get_group_info("12025551234@s.whatsapp.net", plug: {Req.Test, :group_info_not_group})
    end

    test "returns {:error, message} for invalid JID format" do
      Req.Test.stub(:group_info_invalid_jid, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "Invalid JID format: xyz"}))
      end)

      assert {:error, "Invalid JID format: xyz"} =
               Bridge.get_group_info("xyz", plug: {Req.Test, :group_info_invalid_jid})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:group_info_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.get_group_info("120363123456789012@g.us", plug: {Req.Test, :group_info_refused})
    end

    test "returns {:error, :timeout} on request timeout" do
      Req.Test.stub(:group_info_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.get_group_info("120363123456789012@g.us", plug: {Req.Test, :group_info_timeout})
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:group_info_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, group: %{jid: "120363123456789012@g.us", name: "Test"}})
      end)

      Bridge.get_group_info("120363123456789012@g.us", plug: {Req.Test, :group_info_verify})

      assert_receive {:payload, %{"jid" => "120363123456789012@g.us"}}
    end

    test "handles 500 server error" do
      Req.Test.stub(:group_info_500, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"message": "Failed to get group info: timeout"}))
      end)

      assert {:error, "Failed to get group info: timeout"} =
               Bridge.get_group_info("120363123456789012@g.us", plug: {Req.Test, :group_info_500})
    end
  end

  describe "list_contacts/1" do
    test "returns {:ok, result} with contacts and total on success" do
      Req.Test.stub(:list_contacts_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          contacts: [
            %{
              jid: "12025551234@s.whatsapp.net",
              first_name: "John",
              full_name: "John Doe",
              push_name: "Johnny",
              business_name: nil,
              redacted_phone: nil
            },
            %{
              jid: "78834275733504@lid",
              first_name: nil,
              full_name: nil,
              push_name: "Esteban",
              business_name: nil,
              redacted_phone: "+33∙∙∙∙∙∙∙∙53"
            }
          ],
          total: 127
        })
      end)

      assert {:ok, %{contacts: contacts, total: 127}} =
               Bridge.list_contacts(plug: {Req.Test, :list_contacts_success})

      assert length(contacts) == 2
      assert hd(contacts)["jid"] == "12025551234@s.whatsapp.net"
    end

    test "returns empty contacts list when no contacts synced" do
      Req.Test.stub(:list_contacts_empty, fn conn ->
        Req.Test.json(conn, %{success: true, contacts: [], total: 0})
      end)

      assert {:ok, %{contacts: [], total: 0}} =
               Bridge.list_contacts(plug: {Req.Test, :list_contacts_empty})
    end

    test "passes query parameter correctly" do
      test_pid = self()

      Req.Test.stub(:list_contacts_query, fn conn ->
        send(test_pid, {:query_params, conn.query_params})
        Req.Test.json(conn, %{success: true, contacts: [], total: 0})
      end)

      Bridge.list_contacts(query: "John", plug: {Req.Test, :list_contacts_query})

      assert_receive {:query_params, params}
      assert params["query"] == "John"
    end

    test "passes limit and offset parameters correctly" do
      test_pid = self()

      Req.Test.stub(:list_contacts_pagination, fn conn ->
        send(test_pid, {:query_params, conn.query_params})
        Req.Test.json(conn, %{success: true, contacts: [], total: 0})
      end)

      Bridge.list_contacts(limit: 50, offset: 100, plug: {Req.Test, :list_contacts_pagination})

      assert_receive {:query_params, params}
      assert params["limit"] == "50"
      assert params["offset"] == "100"
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:list_contacts_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.list_contacts(plug: {Req.Test, :list_contacts_refused})
    end

    test "returns {:error, :timeout} on timeout" do
      Req.Test.stub(:list_contacts_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.list_contacts(plug: {Req.Test, :list_contacts_timeout})
    end

    test "handles 500 server error" do
      Req.Test.stub(:list_contacts_500, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"message": "Failed to get contacts"}))
      end)

      assert {:error, "Failed to get contacts"} =
               Bridge.list_contacts(plug: {Req.Test, :list_contacts_500})
    end
  end

  describe "merge_chats/3" do
    test "returns {:ok, result} on successful merge" do
      Req.Test.stub(:merge_chats_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Merged 5 messages from 78834275733504@lid into 14155554567@s.whatsapp.net. Source chat deleted.",
          messages_moved: 5
        })
      end)

      assert {:ok, %{message: message, messages_moved: 5}} =
               Bridge.merge_chats("78834275733504@lid", "14155554567@s.whatsapp.net",
                 plug: {Req.Test, :merge_chats_success}
               )

      assert String.contains?(message, "Merged 5 messages")
    end

    test "returns {:error, reason} when source chat doesn't exist" do
      Req.Test.stub(:merge_chats_source_not_found, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "source chat does not exist: unknown@lid"}))
      end)

      assert {:error, "source chat does not exist: unknown@lid"} =
               Bridge.merge_chats("unknown@lid", "14155554567@s.whatsapp.net",
                 plug: {Req.Test, :merge_chats_source_not_found}
               )
    end

    test "returns {:error, reason} when target chat doesn't exist" do
      Req.Test.stub(:merge_chats_target_not_found, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "target chat does not exist: unknown@s.whatsapp.net"}))
      end)

      assert {:error, "target chat does not exist: unknown@s.whatsapp.net"} =
               Bridge.merge_chats("78834275733504@lid", "unknown@s.whatsapp.net",
                 plug: {Req.Test, :merge_chats_target_not_found}
               )
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:merge_chats_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Merged", messages_moved: 0})
      end)

      Bridge.merge_chats("source@lid", "target@s.whatsapp.net", plug: {Req.Test, :merge_chats_verify})

      assert_receive {:payload, %{"source_jid" => "source@lid", "target_jid" => "target@s.whatsapp.net"}}
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:merge_chats_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.merge_chats("source@lid", "target@s.whatsapp.net", plug: {Req.Test, :merge_chats_refused})
    end

    test "returns {:error, :timeout} on timeout" do
      Req.Test.stub(:merge_chats_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.merge_chats("source@lid", "target@s.whatsapp.net", plug: {Req.Test, :merge_chats_timeout})
    end
  end

  describe "get_group_invite_link/2" do
    test "returns {:ok, invite_link} on success" do
      Req.Test.stub(:group_invite_link_success, fn conn ->
        Req.Test.json(conn, %{success: true, invite_link: "https://chat.whatsapp.com/ABC123xyz"})
      end)

      assert {:ok, "https://chat.whatsapp.com/ABC123xyz"} =
               Bridge.get_group_invite_link("120363123456789012@g.us",
                 plug: {Req.Test, :group_invite_link_success}
               )
    end

    test "returns {:ok, invite_link} when resetting link" do
      test_pid = self()

      Req.Test.stub(:group_invite_link_reset, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, invite_link: "https://chat.whatsapp.com/NEW456abc"})
      end)

      assert {:ok, "https://chat.whatsapp.com/NEW456abc"} =
               Bridge.get_group_invite_link("120363123456789012@g.us",
                 reset: true,
                 plug: {Req.Test, :group_invite_link_reset}
               )

      assert_receive {:payload, %{"jid" => "120363123456789012@g.us", "reset" => true}}
    end

    test "returns {:error, reason} when not admin" do
      Req.Test.stub(:group_invite_link_not_admin, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"message": "Failed to get invite link: not a group admin"}))
      end)

      assert {:error, "Failed to get invite link: not a group admin"} =
               Bridge.get_group_invite_link("120363123456789012@g.us",
                 plug: {Req.Test, :group_invite_link_not_admin}
               )
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:group_invite_link_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.get_group_invite_link("120363123456789012@g.us",
                 plug: {Req.Test, :group_invite_link_refused}
               )
    end

    test "returns {:error, :timeout} on timeout" do
      Req.Test.stub(:group_invite_link_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.get_group_invite_link("120363123456789012@g.us",
                 plug: {Req.Test, :group_invite_link_timeout}
               )
    end

    test "sends correct JSON payload without reset" do
      test_pid = self()

      Req.Test.stub(:group_invite_link_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, invite_link: "https://chat.whatsapp.com/ABC123"})
      end)

      Bridge.get_group_invite_link("120363123456789012@g.us", plug: {Req.Test, :group_invite_link_verify})

      assert_receive {:payload, %{"jid" => "120363123456789012@g.us", "reset" => false}}
    end
  end

  describe "join_group/2" do
    test "returns {:ok, result} on successful join with full link" do
      Req.Test.stub(:join_group_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          group_jid: "120363123456789012@g.us",
          message: "Successfully joined group 120363123456789012@g.us"
        })
      end)

      assert {:ok, %{group_jid: "120363123456789012@g.us", message: message}} =
               Bridge.join_group("https://chat.whatsapp.com/ABC123xyz",
                 plug: {Req.Test, :join_group_success}
               )

      assert String.contains?(message, "Successfully joined")
    end

    test "returns {:ok, result} on successful join with just code" do
      test_pid = self()

      Req.Test.stub(:join_group_code, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})

        Req.Test.json(conn, %{
          success: true,
          group_jid: "120363123456789012@g.us",
          message: "Successfully joined group 120363123456789012@g.us"
        })
      end)

      assert {:ok, _} = Bridge.join_group("ABC123xyz", plug: {Req.Test, :join_group_code})

      assert_receive {:payload, %{"invite_link" => "ABC123xyz"}}
    end

    test "returns {:error, reason} when invite link expired" do
      Req.Test.stub(:join_group_expired, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"message": "Failed to join group: invite link expired"}))
      end)

      assert {:error, "Failed to join group: invite link expired"} =
               Bridge.join_group("https://chat.whatsapp.com/EXPIRED123",
                 plug: {Req.Test, :join_group_expired}
               )
    end

    test "returns {:error, reason} when already in group" do
      Req.Test.stub(:join_group_already_member, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"message": "Failed to join group: already a participant"}))
      end)

      assert {:error, "Failed to join group: already a participant"} =
               Bridge.join_group("https://chat.whatsapp.com/ABC123",
                 plug: {Req.Test, :join_group_already_member}
               )
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:join_group_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.join_group("https://chat.whatsapp.com/ABC123",
                 plug: {Req.Test, :join_group_refused}
               )
    end

    test "returns {:error, :timeout} on timeout" do
      Req.Test.stub(:join_group_timeout, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               Bridge.join_group("https://chat.whatsapp.com/ABC123",
                 plug: {Req.Test, :join_group_timeout}
               )
    end
  end

  describe "update_group_name/3" do
    test "returns {:ok, message} on success" do
      Req.Test.stub(:update_group_name_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: ~s(Group name updated to "New Name")})
      end)

      assert {:ok, ~s(Group name updated to "New Name")} =
               Bridge.update_group_name("120363123456789012@g.us", "New Name",
                 plug: {Req.Test, :update_group_name_success}
               )
    end

    test "returns {:error, reason} when name too long" do
      Req.Test.stub(:update_group_name_too_long, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "Group name must be 25 characters or less"}))
      end)

      assert {:error, "Group name must be 25 characters or less"} =
               Bridge.update_group_name("120363123456789012@g.us", "This name is way too long for a group",
                 plug: {Req.Test, :update_group_name_too_long}
               )
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:update_group_name_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.update_group_name("120363123456789012@g.us", "New Name",
                 plug: {Req.Test, :update_group_name_refused}
               )
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:update_group_name_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Updated"})
      end)

      Bridge.update_group_name("120363123456789012@g.us", "Test Group", plug: {Req.Test, :update_group_name_verify})

      assert_receive {:payload, %{"jid" => "120363123456789012@g.us", "name" => "Test Group"}}
    end
  end

  describe "update_group_description/3" do
    test "returns {:ok, message} on success" do
      Req.Test.stub(:update_group_desc_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Group description updated"})
      end)

      assert {:ok, "Group description updated"} =
               Bridge.update_group_description("120363123456789012@g.us", "Welcome to our group!",
                 plug: {Req.Test, :update_group_desc_success}
               )
    end

    test "returns {:ok, message} when clearing description" do
      Req.Test.stub(:update_group_desc_clear, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Group description cleared"})
      end)

      assert {:ok, "Group description cleared"} =
               Bridge.update_group_description("120363123456789012@g.us", "", plug: {Req.Test, :update_group_desc_clear})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:update_group_desc_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.update_group_description("120363123456789012@g.us", "Description",
                 plug: {Req.Test, :update_group_desc_refused}
               )
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:update_group_desc_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Updated"})
      end)

      Bridge.update_group_description("120363123456789012@g.us", "New description",
        plug: {Req.Test, :update_group_desc_verify}
      )

      assert_receive {:payload, %{"jid" => "120363123456789012@g.us", "description" => "New description"}}
    end
  end

  describe "update_group_settings/2" do
    test "returns {:ok, message} when setting locked" do
      Req.Test.stub(:update_group_settings_locked, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Group settings updated: locked (only admins can edit info)"})
      end)

      assert {:ok, "Group settings updated: locked (only admins can edit info)"} =
               Bridge.update_group_settings("120363123456789012@g.us",
                 locked: true,
                 plug: {Req.Test, :update_group_settings_locked}
               )
    end

    test "returns {:ok, message} when setting announce" do
      Req.Test.stub(:update_group_settings_announce, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Group settings updated: announce mode enabled (only admins can send)"
        })
      end)

      assert {:ok, "Group settings updated: announce mode enabled (only admins can send)"} =
               Bridge.update_group_settings("120363123456789012@g.us",
                 announce: true,
                 plug: {Req.Test, :update_group_settings_announce}
               )
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:update_group_settings_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.update_group_settings("120363123456789012@g.us",
                 locked: true,
                 plug: {Req.Test, :update_group_settings_refused}
               )
    end

    test "sends correct JSON payload with both settings" do
      test_pid = self()

      Req.Test.stub(:update_group_settings_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Updated"})
      end)

      Bridge.update_group_settings("120363123456789012@g.us",
        locked: true,
        announce: false,
        plug: {Req.Test, :update_group_settings_verify}
      )

      assert_receive {:payload, %{"jid" => "120363123456789012@g.us", "locked" => true, "announce" => false}}
    end
  end

  describe "update_group_participants/4" do
    test "returns {:ok, result} on successful add" do
      Req.Test.stub(:update_participants_add, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully added to group: 1 participant(s)",
          participants: [%{"jid" => "12025551234@s.whatsapp.net", "error_code" => 0}]
        })
      end)

      assert {:ok, %{message: message, participants: [%{jid: "12025551234@s.whatsapp.net", error_code: 0}]}} =
               Bridge.update_group_participants(
                 "120363123456789012@g.us",
                 ["12025551234@s.whatsapp.net"],
                 "add",
                 plug: {Req.Test, :update_participants_add}
               )

      assert String.contains?(message, "added to group")
    end

    test "returns {:ok, result} on successful promote" do
      Req.Test.stub(:update_participants_promote, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully promoted in group: 1 participant(s)",
          participants: [%{"jid" => "12025551234@s.whatsapp.net", "error_code" => 0}]
        })
      end)

      assert {:ok, %{message: message, participants: _}} =
               Bridge.update_group_participants(
                 "120363123456789012@g.us",
                 ["12025551234@s.whatsapp.net"],
                 "promote",
                 plug: {Req.Test, :update_participants_promote}
               )

      assert String.contains?(message, "promoted in group")
    end

    test "returns {:ok, result} with error codes for failed participants" do
      Req.Test.stub(:update_participants_partial_fail, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          message: "Successfully added to group: 2 participant(s)",
          participants: [
            %{"jid" => "12025551234@s.whatsapp.net", "error_code" => 0},
            %{"jid" => "12025559999@s.whatsapp.net", "error_code" => 403}
          ]
        })
      end)

      assert {:ok, %{message: _, participants: participants}} =
               Bridge.update_group_participants(
                 "120363123456789012@g.us",
                 ["12025551234@s.whatsapp.net", "12025559999@s.whatsapp.net"],
                 "add",
                 plug: {Req.Test, :update_participants_partial_fail}
               )

      # First participant succeeded
      assert Enum.find(participants, &(&1.jid == "12025551234@s.whatsapp.net")).error_code == 0
      # Second participant failed with error code
      assert Enum.find(participants, &(&1.jid == "12025559999@s.whatsapp.net")).error_code == 403
    end

    test "returns {:error, reason} when not admin" do
      Req.Test.stub(:update_participants_not_admin, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"message": "Failed to add participants: not a group admin"}))
      end)

      assert {:error, "Failed to add participants: not a group admin"} =
               Bridge.update_group_participants(
                 "120363123456789012@g.us",
                 ["12025551234@s.whatsapp.net"],
                 "add",
                 plug: {Req.Test, :update_participants_not_admin}
               )
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:update_participants_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.update_group_participants(
                 "120363123456789012@g.us",
                 ["12025551234@s.whatsapp.net"],
                 "add",
                 plug: {Req.Test, :update_participants_refused}
               )
    end

    test "sends correct JSON payload" do
      test_pid = self()

      Req.Test.stub(:update_participants_verify, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Done", participants: []})
      end)

      Bridge.update_group_participants(
        "120363123456789012@g.us",
        ["12025551234@s.whatsapp.net", "44123456789@s.whatsapp.net"],
        "remove",
        plug: {Req.Test, :update_participants_verify}
      )

      assert_receive {:payload,
                      %{
                        "jid" => "120363123456789012@g.us",
                        "participants" => ["12025551234@s.whatsapp.net", "44123456789@s.whatsapp.net"],
                        "action" => "remove"
                      }}
    end

    test "returns {:error, rate_limit_message} on 429" do
      Req.Test.stub(:update_participants_rate_limit, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(429, ~s({"message": "Too many requests"}))
      end)

      assert {:error, msg} =
               Bridge.update_group_participants(
                 "120363123456789012@g.us",
                 ["12025551234@s.whatsapp.net"],
                 "add",
                 plug: {Req.Test, :update_participants_rate_limit}
               )

      assert String.contains?(msg, "Rate limited")
      assert String.contains?(msg, "Too many requests")
    end
  end

  describe "rate limit handling" do
    test "send_message returns clear error on 429" do
      Req.Test.stub(:send_rate_limit, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(429, ~s({"message": "Rate limit exceeded"}))
      end)

      assert {:error, msg} = Bridge.send_message("12025551234", "test", plug: {Req.Test, :send_rate_limit})
      assert String.contains?(msg, "Rate limited by WhatsApp")
      assert String.contains?(msg, "Rate limit exceeded")
      assert String.contains?(msg, "Wait a few minutes")
    end

    test "returns generic rate limit message when no body message" do
      Req.Test.stub(:send_rate_limit_no_msg, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(429, "")
      end)

      assert {:error, msg} = Bridge.send_message("12025551234", "test", plug: {Req.Test, :send_rate_limit_no_msg})
      assert String.contains?(msg, "Rate limited by WhatsApp")
      assert String.contains?(msg, "Wait a few minutes")
    end
  end

  describe "get_privacy_settings/1" do
    test "returns {:ok, settings} on success" do
      Req.Test.stub(:privacy_settings_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          group_add: "contacts",
          last_seen: "contacts",
          status: "all",
          profile: "contacts",
          read_receipts: "all",
          online: "all",
          call_add: "known"
        })
      end)

      assert {:ok, settings} = Bridge.get_privacy_settings(plug: {Req.Test, :privacy_settings_success})
      assert settings.group_add == "contacts"
      assert settings.last_seen == "contacts"
      assert settings.status == "all"
      assert settings.profile == "contacts"
      assert settings.read_receipts == "all"
      assert settings.online == "all"
      assert settings.call_add == "known"
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:privacy_settings_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.get_privacy_settings(plug: {Req.Test, :privacy_settings_refused})
    end
  end

  describe "set_privacy_setting/3" do
    test "returns {:ok, message} on success" do
      test_pid = self()

      Req.Test.stub(:set_privacy_success, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Privacy setting 'last' updated to 'contacts'"})
      end)

      assert {:ok, "Privacy setting 'last' updated to 'contacts'"} =
               Bridge.set_privacy_setting("last", "contacts", plug: {Req.Test, :set_privacy_success})

      assert_receive {:payload, %{"setting" => "last", "value" => "contacts"}}
    end

    test "returns {:error, reason} on invalid setting" do
      Req.Test.stub(:set_privacy_invalid, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          400,
          ~s({"message": "setting must be one of: groupadd, last, status, profile, readreceipts, online, calladd"})
        )
      end)

      assert {:error, msg} =
               Bridge.set_privacy_setting("invalid", "all", plug: {Req.Test, :set_privacy_invalid})

      assert String.contains?(msg, "setting must be one of")
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:set_privacy_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.set_privacy_setting("last", "contacts", plug: {Req.Test, :set_privacy_refused})
    end
  end

  describe "get_business_profile/2" do
    test "returns {:ok, profile} on success with full profile" do
      Req.Test.stub(:business_profile_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          profile: %{
            jid: "12025551234@s.whatsapp.net",
            address: "123 Main St",
            email: "contact@example.com",
            categories: [%{id: "123", name: "Retail"}],
            business_hours_timezone: "America/New_York",
            business_hours: [
              %{day_of_week: "monday", mode: "open", open_time: "09:00", close_time: "17:00"}
            ]
          }
        })
      end)

      assert {:ok, profile} =
               Bridge.get_business_profile("12025551234@s.whatsapp.net", plug: {Req.Test, :business_profile_success})

      assert profile["jid"] == "12025551234@s.whatsapp.net"
      assert profile["address"] == "123 Main St"
      assert profile["email"] == "contact@example.com"
      assert length(profile["categories"]) == 1
    end

    test "returns {:error, reason} when not a business account" do
      Req.Test.stub(:business_profile_not_business, fn conn ->
        Req.Test.json(conn, %{
          success: false,
          message: "Contact is not a business account"
        })
      end)

      assert {:error, "Contact is not a business account"} =
               Bridge.get_business_profile("12025551234@s.whatsapp.net", plug: {Req.Test, :business_profile_not_business})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:business_profile_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.get_business_profile("12025551234@s.whatsapp.net", plug: {Req.Test, :business_profile_refused})
    end
  end

  describe "reject_call/3" do
    test "returns {:ok, message} on success" do
      test_pid = self()

      Req.Test.stub(:reject_call_success, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, message: "Call abc123 from 12025551234@s.whatsapp.net rejected"})
      end)

      assert {:ok, "Call abc123 from 12025551234@s.whatsapp.net rejected"} =
               Bridge.reject_call("12025551234@s.whatsapp.net", "abc123", plug: {Req.Test, :reject_call_success})

      assert_receive {:payload, %{"call_from" => "12025551234@s.whatsapp.net", "call_id" => "abc123"}}
    end

    test "returns {:error, reason} on invalid JID" do
      Req.Test.stub(:reject_call_invalid, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "Invalid call_from JID format"}))
      end)

      assert {:error, "Invalid call_from JID format"} =
               Bridge.reject_call("invalid", "abc123", plug: {Req.Test, :reject_call_invalid})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:reject_call_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.reject_call("12025551234@s.whatsapp.net", "abc123", plug: {Req.Test, :reject_call_refused})
    end
  end

  describe "list_newsletters/1" do
    test "returns {:ok, list} on success with newsletters" do
      Req.Test.stub(:list_newsletters_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          newsletters: [
            %{
              id: "123456789@newsletter",
              name: "Tech News",
              description: "Latest tech updates",
              subscriber_count: 50_000,
              invite_link: "https://whatsapp.com/channel/abc123",
              created_at: "2024-01-15T10:00:00Z",
              is_muted: false
            },
            %{
              id: "987654321@newsletter",
              name: "Daily Digest",
              description: "Your daily news",
              subscriber_count: 1_200_000,
              is_muted: true
            }
          ]
        })
      end)

      assert {:ok, newsletters} = Bridge.list_newsletters(plug: {Req.Test, :list_newsletters_success})
      assert length(newsletters) == 2
      assert hd(newsletters)["id"] == "123456789@newsletter"
      assert hd(newsletters)["name"] == "Tech News"
      assert hd(newsletters)["subscriber_count"] == 50_000
    end

    test "returns {:ok, []} when not subscribed to any newsletters" do
      Req.Test.stub(:list_newsletters_empty, fn conn ->
        Req.Test.json(conn, %{success: true, newsletters: []})
      end)

      assert {:ok, []} = Bridge.list_newsletters(plug: {Req.Test, :list_newsletters_empty})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:list_newsletters_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.list_newsletters(plug: {Req.Test, :list_newsletters_refused})
    end
  end

  describe "get_newsletter_info/2" do
    test "returns {:ok, newsletter} on success" do
      Req.Test.stub(:newsletter_info_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          newsletter: %{
            id: "123456789@newsletter",
            name: "Tech News",
            description: "Latest technology news and updates",
            subscriber_count: 50_000,
            invite_link: "https://whatsapp.com/channel/abc123",
            created_at: "2024-01-15T10:00:00Z",
            is_muted: false
          }
        })
      end)

      assert {:ok, newsletter} =
               Bridge.get_newsletter_info("123456789@newsletter", plug: {Req.Test, :newsletter_info_success})

      assert newsletter["id"] == "123456789@newsletter"
      assert newsletter["name"] == "Tech News"
      assert newsletter["subscriber_count"] == 50_000
    end

    test "returns {:error, reason} when newsletter not found" do
      Req.Test.stub(:newsletter_info_not_found, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, ~s({"message": "Newsletter not found"}))
      end)

      assert {:error, "Newsletter not found"} =
               Bridge.get_newsletter_info("nonexistent@newsletter", plug: {Req.Test, :newsletter_info_not_found})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:newsletter_info_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.get_newsletter_info("123456789@newsletter", plug: {Req.Test, :newsletter_info_refused})
    end
  end

  describe "get_newsletter_messages/2" do
    test "returns {:ok, messages} on success" do
      Req.Test.stub(:newsletter_messages_success, fn conn ->
        Req.Test.json(conn, %{
          success: true,
          messages: [
            %{
              server_id: 100,
              text: "Check out our latest article!",
              timestamp: "2024-12-10T15:30:00Z",
              view_count: 25_000,
              media_type: ""
            },
            %{
              server_id: 99,
              text: "Big announcement coming soon",
              timestamp: "2024-12-09T10:00:00Z",
              view_count: 45_000,
              media_type: "image"
            }
          ]
        })
      end)

      assert {:ok, messages} =
               Bridge.get_newsletter_messages("123456789@newsletter", plug: {Req.Test, :newsletter_messages_success})

      assert length(messages) == 2
      assert hd(messages)["text"] == "Check out our latest article!"
      assert hd(messages)["view_count"] == 25_000
    end

    test "returns {:ok, []} when no messages" do
      Req.Test.stub(:newsletter_messages_empty, fn conn ->
        Req.Test.json(conn, %{success: true, messages: []})
      end)

      assert {:ok, []} =
               Bridge.get_newsletter_messages("123456789@newsletter", plug: {Req.Test, :newsletter_messages_empty})
    end

    test "passes count and before params to API" do
      test_pid = self()

      Req.Test.stub(:newsletter_messages_params, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, messages: []})
      end)

      Bridge.get_newsletter_messages("123456789@newsletter",
        count: 10,
        before: 50,
        plug: {Req.Test, :newsletter_messages_params}
      )

      assert_receive {:payload, %{"jid" => "123456789@newsletter", "count" => 10, "before" => 50}}
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:newsletter_messages_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.get_newsletter_messages("123456789@newsletter", plug: {Req.Test, :newsletter_messages_refused})
    end
  end

  describe "follow_newsletter/2" do
    test "returns {:ok, message} on success" do
      Req.Test.stub(:follow_newsletter_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Successfully followed newsletter"})
      end)

      assert {:ok, "Successfully followed newsletter"} =
               Bridge.follow_newsletter("123456789@newsletter", plug: {Req.Test, :follow_newsletter_success})
    end

    test "returns {:error, reason} when already following" do
      Req.Test.stub(:follow_newsletter_already, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "Already following this newsletter"}))
      end)

      assert {:error, "Already following this newsletter"} =
               Bridge.follow_newsletter("123456789@newsletter", plug: {Req.Test, :follow_newsletter_already})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:follow_newsletter_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.follow_newsletter("123456789@newsletter", plug: {Req.Test, :follow_newsletter_refused})
    end
  end

  describe "unfollow_newsletter/2" do
    test "returns {:ok, message} on success" do
      Req.Test.stub(:unfollow_newsletter_success, fn conn ->
        Req.Test.json(conn, %{success: true, message: "Successfully unfollowed newsletter"})
      end)

      assert {:ok, "Successfully unfollowed newsletter"} =
               Bridge.unfollow_newsletter("123456789@newsletter", plug: {Req.Test, :unfollow_newsletter_success})
    end

    test "returns {:error, reason} when not following" do
      Req.Test.stub(:unfollow_newsletter_not_following, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message": "Not following this newsletter"}))
      end)

      assert {:error, "Not following this newsletter"} =
               Bridge.unfollow_newsletter("123456789@newsletter", plug: {Req.Test, :unfollow_newsletter_not_following})
    end

    test "returns {:error, :bridge_not_running} on connection refused" do
      Req.Test.stub(:unfollow_newsletter_refused, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :bridge_not_running} =
               Bridge.unfollow_newsletter("123456789@newsletter", plug: {Req.Test, :unfollow_newsletter_refused})
    end
  end
end
