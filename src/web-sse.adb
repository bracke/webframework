with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Web.SSE is

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

   --  A single line: CR and LF removed, so a caller value cannot forge a new
   --  SSE field or terminate the event.
   function Single_Line (S : String) return String is
      R : String (1 .. S'Length);
      N : Natural := 0;
   begin
      for C of S loop
         if C /= CR and then C /= LF then
            N := N + 1;
            R (N) := C;
         end if;
      end loop;
      return R (1 .. N);
   end Single_Line;

   --  Strip a single trailing CR (from a CRLF-terminated data line).
   function Trim_CR (S : String) return String is
     (if S'Length > 0 and then S (S'Last) = CR
      then S (S'First .. S'Last - 1) else S);

   function Response_Headers return String is
   begin
      return "HTTP/1.1 200 OK" & CR & LF
        & "Content-Type: text/event-stream; charset=utf-8" & CR & LF
        & "Cache-Control: no-cache" & CR & LF
        & "Connection: keep-alive" & CR & LF
        & "X-Accel-Buffering: no" & CR & LF
        & CR & LF;
   end Response_Headers;

   function Format_Event
     (Data  : String;
      Event : String := "";
      Id    : String := "") return String
   is
      Buf   : Unbounded_String;
      Start : Integer := Data'First;
      NL    : Integer;
   begin
      if Event'Length > 0 then
         Append (Buf, "event: " & Single_Line (Event) & LF);
      end if;
      if Id'Length > 0 then
         Append (Buf, "id: " & Single_Line (Id) & LF);
      end if;

      --  One "data:" line per line of Data (split on LF, trailing CR trimmed);
      --  empty data still emits one "data:" line.
      loop
         NL := 0;
         for I in Start .. Data'Last loop
            if Data (I) = LF then
               NL := I;
               exit;
            end if;
         end loop;
         if NL = 0 then
            Append (Buf, "data: " & Trim_CR (Data (Start .. Data'Last)) & LF);
            exit;
         else
            Append (Buf, "data: " & Trim_CR (Data (Start .. NL - 1)) & LF);
            Start := NL + 1;
            exit when Start > Data'Last;   --  data ended on a newline
         end if;
      end loop;

      Append (Buf, LF);   --  the blank line terminates the event
      return To_String (Buf);
   end Format_Event;

   function Format_Comment (Text : String) return String is
     (": " & Single_Line (Text) & LF & LF);

   function Format_Retry (Milliseconds : Natural) return String is
      Img : constant String := Natural'Image (Milliseconds);
   begin
      --  Natural'Image has a leading space; drop it.
      return "retry: " & Img (Img'First + 1 .. Img'Last) & LF & LF;
   end Format_Retry;

   --  Write Text, mapping a closed/broken connection to Ok = False.
   procedure Write
     (Conn : in out Web.Connection.Connection_Type;
      Text : String;
      Ok   : out Boolean) is
   begin
      Web.Connection.Send_All (Conn, Text);
      Ok := True;
   exception
      when others =>
         Ok := False;
   end Write;

   procedure Send_Event
     (Conn  : in out Web.Connection.Connection_Type;
      Data  : String;
      Event : String := "";
      Id    : String := "";
      Ok    : out Boolean) is
   begin
      Write (Conn, Format_Event (Data, Event, Id), Ok);
   end Send_Event;

   procedure Send_Comment
     (Conn : in out Web.Connection.Connection_Type;
      Text : String;
      Ok   : out Boolean) is
   begin
      Write (Conn, Format_Comment (Text), Ok);
   end Send_Comment;

   procedure Send_Retry
     (Conn         : in out Web.Connection.Connection_Type;
      Milliseconds : Natural;
      Ok           : out Boolean) is
   begin
      Write (Conn, Format_Retry (Milliseconds), Ok);
   end Send_Retry;

end Web.SSE;
