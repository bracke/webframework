package body Web.Http_Body is

   use type Ada.Streams.Stream_Element_Offset;

   procedure Start
     (Self           : in out Reader;
      Conn           : Connection_Ref;
      Leftover       : Ada.Streams.Stream_Element_Array;
      Content_Length : Natural)
   is
   begin
      Self.Conn     := Conn;
      Self.Left_Len := Leftover'Length;
      Self.Left_Pos := 0;
      if Leftover'Length > 0 then
         Self.Leftover (1 .. Leftover'Length) := Leftover;
      end if;
      --  The leftover already holds the first Left_Len content bytes; the rest
      --  come from the socket. Never expect more than Content-Length total.
      if Content_Length >= Self.Left_Len then
         Self.To_Read := Content_Length - Self.Left_Len;
      else
         --  More leftover than declared: clamp to the declared length.
         Self.Left_Len := Content_Length;
         Self.To_Read  := 0;
      end if;
   end Start;

   procedure Read
     (Self   : in out Reader;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Done   : out Boolean;
      Closed : out Boolean)
   is
   begin
      Last   := Buffer'First - 1;
      Closed := False;

      if Self.Left_Pos < Self.Left_Len then
         --  Deliver from the leftover first.
         declare
            Available : constant Natural := Self.Left_Len - Self.Left_Pos;
            Count     : constant Natural :=
              Natural'Min (Natural (Buffer'Length), Available);
         begin
            Buffer (Buffer'First .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1) :=
              Self.Leftover
                (Ada.Streams.Stream_Element_Offset (Self.Left_Pos + 1) ..
                 Ada.Streams.Stream_Element_Offset (Self.Left_Pos + Count));
            Self.Left_Pos := Self.Left_Pos + Count;
            Last := Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
         end;

      elsif Self.To_Read > 0 and then Self.Conn /= null then
         --  Then pull from the connection, never past the declared length.
         declare
            Want : constant Natural :=
              Natural'Min (Natural (Buffer'Length), Self.To_Read);
            Recv_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Web.Connection.Receive
              (Self.Conn.all,
               Buffer (Buffer'First .. Buffer'First + Ada.Streams.Stream_Element_Offset (Want) - 1),
               Recv_Last);
            if Recv_Last < Buffer'First then
               --  Connection closed before the whole body arrived.
               Closed := True;
               Self.To_Read := 0;
            else
               Last := Recv_Last;
               Self.To_Read :=
                 Self.To_Read - Natural (Recv_Last - Buffer'First + 1);
            end if;
         end;
      end if;

      Done := (Self.Left_Pos >= Self.Left_Len) and then Self.To_Read = 0;
   end Read;

   function Remaining (Self : Reader) return Natural is
     ((Self.Left_Len - Self.Left_Pos) + Self.To_Read);

end Web.Http_Body;
