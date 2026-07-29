with Ada.Strings.Unbounded;

--  App.Smtp_Catcher -- a minimal, honest, in-process SMTP server used as a
--  development "mail catcher". It binds a real TCP listener on 127.0.0.1:2525
--  and speaks just enough SMTP (plaintext, no AUTH, no STARTTLS) to accept one
--  message per connection: 220 greeting, EHLO/HELO, MAIL FROM, RCPT TO, DATA
--  (read to the CRLF "." CRLF terminator, un-dot-stuffed), then 250. The raw
--  RFC 5322 bytes smtplib transmits are captured verbatim into a bounded store
--  (the last 20 submissions) for the demo page and the integration test.
--
--  This is the real thing over a real socket: notifications -> notifications_email
--  -> smtplib -> this catcher. Nothing is mocked; the bytes on the wire are what
--  land here.
package App.Smtp_Catcher is

   use Ada.Strings.Unbounded;

   --  The fixed loopback port the catcher listens on and smtplib targets.
   Listen_Port : constant := 2525;

   type Start_Status is (Ready, Bind_Error, Already_Started);

   --  Bind the listener and start the accept task. Idempotent per process.
   procedure Start (Status : out Start_Status);

   --  Stop the accept task and close the listener. Idempotent; safe at shutdown.
   procedure Stop;

   function Port return Positive;

   --  One captured submission: the SMTP envelope (MAIL FROM / the first RCPT TO)
   --  and the raw message bytes exactly as received (headers + body).
   type Captured_Mail is record
      Envelope_From : Unbounded_String;
      Envelope_To   : Unbounded_String;
      Raw_Message   : Unbounded_String;
   end record;

   --  How many messages the catcher currently holds (0 .. 20).
   function Count return Natural;

   --  The Index'th captured message, oldest first. Found is False when Index is
   --  out of range.
   procedure Get (Index : Positive; Mail : out Captured_Mail; Found : out Boolean);

end App.Smtp_Catcher;
