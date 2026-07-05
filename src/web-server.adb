with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with System;
with Web.Config;
with Web.Connection;
with Web.Errors;
with Web.Logging;
with Web.Security;
with Web.Static;
with Web.TLS;
with Web.WebSocket;

package body Web.Server is
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use type GNAT.Sockets.Socket_Type;

   package Route_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Route_Handler);

   package Socket_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => WebSocket_Handler);

   type Compression_Choice is (No_Compression, GZip_Compression, Deflate_Compression);

   Routes : Route_Maps.Map;
   Sockets : Socket_Maps.Map;
   Static_Prefix : Unbounded_String;
   Static_Dir : Unbounded_String;

   protected TLS_State is
      procedure Initialize (Config : Web.TLS.Server_Config);
      procedure Reload (Config : Web.TLS.Server_Config);
      function Accept_Connection (Socket : GNAT.Sockets.Socket_Type) return System.Address;
      procedure Finalize;
   private
      Context : Web.TLS.Context;
   end TLS_State;

   protected Server_State is
      procedure Started
        (Socket  : GNAT.Sockets.Socket_Type;
         Address : GNAT.Sockets.Sock_Addr_Type);
      procedure Request_Stop
        (Address     : out GNAT.Sockets.Sock_Addr_Type;
         Should_Wake : out Boolean);
      procedure Finished;
      function Stopping return Boolean;
   private
      Listener : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Bound_Address : GNAT.Sockets.Sock_Addr_Type;
      Stop_Requested : Boolean := False;
   end Server_State;

   protected Server_Config is
      procedure Configure (Config : Web.Config.Config_Type);
      function Mode return Web.Config.Mode_Type;
      function Allowed_Host return String;
      function Max_Request_Size return Natural;
      function Enable_Compression return Boolean;
      function Compression_Min_Size return Natural;
   private
      Current_Mode : Web.Config.Mode_Type := Web.Config.Default_Config.Mode;
      Current_Allowed_Host : Unbounded_String :=
        To_Unbounded_String (Web.Config.Default_Config.Allowed_Host);
      Current_Max_Request_Size : Natural := Web.Config.Default_Config.Max_Request_Size;
      Current_Enable_Compression : Boolean := Web.Config.Default_Config.Enable_Compression;
      Current_Compression_Min_Size : Natural := Web.Config.Default_Config.Compression_Min_Size;
   end Server_Config;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   protected body TLS_State is
      procedure Initialize (Config : Web.TLS.Server_Config) is
      begin
         Web.TLS.Initialize_Server (Context, Config);
      end Initialize;

      procedure Reload (Config : Web.TLS.Server_Config) is
      begin
         Web.TLS.Reload_Server (Context, Config);
      end Reload;

      function Accept_Connection (Socket : GNAT.Sockets.Socket_Type) return System.Address is
      begin
         return Web.TLS.Accept_Connection (Context, Socket);
      end Accept_Connection;

      procedure Finalize is
      begin
         Web.TLS.Finalize (Context);
      end Finalize;
   end TLS_State;

   protected body Server_State is
      procedure Started
        (Socket  : GNAT.Sockets.Socket_Type;
         Address : GNAT.Sockets.Sock_Addr_Type) is
      begin
         Listener := Socket;
         Bound_Address := Address;
         Stop_Requested := False;
      end Started;

      procedure Request_Stop
        (Address     : out GNAT.Sockets.Sock_Addr_Type;
         Should_Wake : out Boolean) is
      begin
         Stop_Requested := True;
         Address := Bound_Address;
         Should_Wake := Listener /= GNAT.Sockets.No_Socket;
      end Request_Stop;

      procedure Finished is
      begin
         if Listener /= GNAT.Sockets.No_Socket then
            begin
               GNAT.Sockets.Close_Socket (Listener);
            exception
               when others =>
                  null;
            end;
         end if;
         Listener := GNAT.Sockets.No_Socket;
         Stop_Requested := False;
      end Finished;

      function Stopping return Boolean is
      begin
         return Stop_Requested;
      end Stopping;
   end Server_State;

   protected body Server_Config is
      procedure Configure (Config : Web.Config.Config_Type) is
      begin
         Current_Mode := Config.Mode;
         Current_Allowed_Host := To_Unbounded_String (Trim (Config.Allowed_Host, Ada.Strings.Both));
         Current_Max_Request_Size := Config.Max_Request_Size;
         Current_Enable_Compression := Config.Enable_Compression;
         Current_Compression_Min_Size := Config.Compression_Min_Size;
      end Configure;

      function Mode return Web.Config.Mode_Type is
      begin
         return Current_Mode;
      end Mode;

      function Allowed_Host return String is
      begin
         return To_String (Current_Allowed_Host);
      end Allowed_Host;

      function Max_Request_Size return Natural is
      begin
         return Current_Max_Request_Size;
      end Max_Request_Size;

      function Enable_Compression return Boolean is
      begin
         return Current_Enable_Compression;
      end Enable_Compression;

      function Compression_Min_Size return Natural is
      begin
         return Current_Compression_Min_Size;
      end Compression_Min_Size;
   end Server_Config;

   function Trimmed_Image (Value : Natural) return String is
   begin
      return Trim (Natural'Image (Value), Ada.Strings.Both);
   end Trimmed_Image;

   function Is_Token_Character (Ch : Character) return Boolean is
   begin
      return (Ch in 'A' .. 'Z')
        or else (Ch in 'a' .. 'z')
        or else (Ch in '0' .. '9')
        or else Ch = '!'
        or else Ch = '#'
        or else Ch = '$'
        or else Ch = '%'
        or else Ch = '&'
        or else Ch = Character'Val (39)
        or else Ch = '*'
        or else Ch = '+'
        or else Ch = '-'
        or else Ch = '.'
        or else Ch = '^'
        or else Ch = '_'
        or else Ch = '`'
        or else Ch = '|'
        or else Ch = '~';
   end Is_Token_Character;

   function Is_Header_Name (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;

      for Ch of Value loop
         if not Is_Token_Character (Ch) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Header_Name;

   function Is_Header_Value (Value : String) return Boolean is
   begin
      for Ch of Value loop
         if (Character'Pos (Ch) < 32 and then Ch /= Character'Val (9))
           or else Character'Pos (Ch) = 127
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Header_Value;

   function Is_Method_Name (Value : String) return Boolean is
   begin
      return Is_Header_Name (Value);
   end Is_Method_Name;

   function Is_Request_Target (Value : String) return Boolean is
      Query_Position : constant Natural := Index (Value, "?");
   begin
      if Value'Length = 0
        or else Value (Value'First) /= '/'
        or else Index (Value, "#") /= 0
      then
         return False;
      end if;

      for Ch of Value loop
         if Character'Pos (Ch) < 33 or else Character'Pos (Ch) > 126 then
            return False;
         end if;
      end loop;

      if Query_Position = 0 then
         return Web.Security.Is_Safe_Path (Value);
      end if;

      return Query_Position > Value'First
        and then Web.Security.Is_Safe_Path (Value (Value'First .. Query_Position - 1));
   end Is_Request_Target;

   function Header_Value (Data : String; Name : String) return String is
      Header_End : constant Natural := Index (Data, CRLF & CRLF);
      Header     : constant String :=
        (if Header_End = 0 then Data else Data (Data'First .. Header_End - 1));
      Prefix     : constant String := Ada.Characters.Handling.To_Lower (Name) & ":";
      Cursor      : Natural := Header'First;
      Line_End    : Natural;
   begin
      loop
         Line_End := Index (Header (Cursor .. Header'Last), CRLF);
         if Line_End = 0 then
            Line_End := Header'Last + 1;
         end if;

         declare
            Line       : constant String := Header (Cursor .. Line_End - 1);
            Lower_Line : constant String := Ada.Characters.Handling.To_Lower (Line);
         begin
            if Index (Lower_Line, Prefix) = Line'First then
               return Trim (Line (Line'First + Prefix'Length .. Line'Last), Ada.Strings.Both);
            end if;
         end;

         exit when Line_End > Header'Last;
         Cursor := Line_End + CRLF'Length;
      end loop;

      return "";
   end Header_Value;

   function Has_Header_Token (Data : String; Name : String; Token : String) return Boolean is
      Value       : constant String := Ada.Characters.Handling.To_Lower (Header_Value (Data, Name));
      Lower_Token : constant String := Ada.Characters.Handling.To_Lower (Token);
      Start_Pos   : Natural := Value'First;
      Comma_Pos   : Natural;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      loop
         Comma_Pos := Index (Value (Start_Pos .. Value'Last), ",");
         declare
            Last_Pos : constant Natural :=
              (if Comma_Pos = 0 then Value'Last else Comma_Pos - 1);
            Item     : constant String := Trim (Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
         begin
            if Item = Lower_Token then
               return True;
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      return False;
   end Has_Header_Token;

   function Q_Value (Parameters : String) return Natural is
      Start_Pos : Natural := Parameters'First;
      Stop_Pos  : Natural;
   begin
      if Parameters'Length = 0 then
         return 1000;
      end if;

      loop
         Stop_Pos := Index (Parameters (Start_Pos .. Parameters'Last), ";");
         declare
            Last_Pos : constant Natural :=
              (if Stop_Pos = 0 then Parameters'Last else Stop_Pos - 1);
            Item     : constant String :=
              Trim (Parameters (Start_Pos .. Last_Pos), Ada.Strings.Both);
            Lower    : constant String := Ada.Characters.Handling.To_Lower (Item);
         begin
            if Lower'Length >= 3
              and then Lower (Lower'First .. Lower'First + 1) = "q="
            then
               declare
                  Value : constant String :=
                    Trim (Lower (Lower'First + 2 .. Lower'Last), Ada.Strings.Both);
               begin
                  if Value = "0" then
                     return 0;
                  end if;

                  if Value = "1" then
                     return 1000;
                  end if;

                  if Value'Length > 2
                    and then Value (Value'First .. Value'First + 1) = "0."
                  then
                     declare
                        Result : Natural := 0;
                        Factor : Natural := 100;
                        Fraction_Length : Natural := 0;
                     begin
                        for Ch of Value (Value'First + 2 .. Value'Last) loop
                           if Ch not in '0' .. '9' then
                              return 0;
                           end if;
                           Fraction_Length := Fraction_Length + 1;
                           if Fraction_Length > 3 then
                              return 0;
                           end if;
                           Result :=
                             Result + (Character'Pos (Ch) - Character'Pos ('0')) * Factor;
                           Factor := Factor / 10;
                        end loop;

                        if Fraction_Length = 0 then
                           return 0;
                        end if;

                        return Result;
                     end;
                  elsif Value'Length > 2
                    and then Value (Value'First .. Value'First + 1) = "1."
                  then
                     declare
                        Fraction_Length : Natural := 0;
                     begin
                        for Ch of Value (Value'First + 2 .. Value'Last) loop
                           if Ch /= '0' then
                              return 0;
                           end if;
                           Fraction_Length := Fraction_Length + 1;
                           if Fraction_Length > 3 then
                              return 0;
                           end if;
                        end loop;

                        if Fraction_Length = 0 then
                           return 0;
                        end if;

                        return 1000;
                     end;
                  end if;

                  return 0;
               end;
            end if;
         end;

         exit when Stop_Pos = 0;
         Start_Pos := Stop_Pos + 1;
      end loop;

      return 1000;
   end Q_Value;

   function Negotiated_Encoding_Q
     (Request : Web.Request.Request_Type;
      Token   : String;
      Absent_Header_Q : Natural;
      Absent_Token_Q  : Natural) return Natural
   is
      Value       : constant String :=
        Ada.Characters.Handling.To_Lower (Web.Request.Header (Request, "Accept-Encoding"));
      Lower_Token : constant String := Ada.Characters.Handling.To_Lower (Token);
      Start_Pos   : Natural := Value'First;
      Comma_Pos   : Natural;
      Explicit     : Boolean := False;
      Explicit_Q   : Natural := 0;
      Wildcard     : Boolean := False;
      Wildcard_Q   : Natural := 0;
   begin
      if not Web.Request.Has_Header (Request, "Accept-Encoding") then
         return Absent_Header_Q;
      end if;

      loop
         Comma_Pos := Index (Value (Start_Pos .. Value'Last), ",");
         declare
            Last_Pos      : constant Natural :=
              (if Comma_Pos = 0 then Value'Last else Comma_Pos - 1);
            Item          : constant String := Trim (Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
            Parameter_Pos : constant Natural := Index (Item, ";");
            Name          : constant String :=
              (if Parameter_Pos = 0
               then Item
               else Trim (Item (Item'First .. Parameter_Pos - 1), Ada.Strings.Both));
            Parameters    : constant String :=
              (if Parameter_Pos = 0 then "" else Item (Parameter_Pos + 1 .. Item'Last));
         begin
            if Name = Lower_Token then
               Explicit := True;
               Explicit_Q := Q_Value (Parameters);
            elsif Name = "*" then
               Wildcard := True;
               Wildcard_Q := Q_Value (Parameters);
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      if Explicit then
         return Explicit_Q;
      elsif Wildcard then
         return Wildcard_Q;
      end if;

      return Absent_Token_Q;
   end Negotiated_Encoding_Q;

   function Response_Encoding_Q
     (Request : Web.Request.Request_Type;
      Token   : String) return Natural
   is
   begin
      return Negotiated_Encoding_Q (Request, Token, 0, 0);
   end Response_Encoding_Q;

   function Identity_Encoding_Q (Request : Web.Request.Request_Type) return Natural is
   begin
      return Negotiated_Encoding_Q (Request, "identity", 1000, 1000);
   end Identity_Encoding_Q;

   function Response_Is_Acceptable
     (Request  : Web.Request.Request_Type;
      Response : Web.Response.Response_Type) return Boolean
   is
      Content_Encoding : constant String := Web.Response.Header (Response, "Content-Encoding");
   begin
      if Content_Encoding'Length = 0 then
         return Identity_Encoding_Q (Request) > 0;
      end if;

      return Response_Encoding_Q (Request, Content_Encoding) > 0;
   end Response_Is_Acceptable;

   function Response_Compression (Request : Web.Request.Request_Type) return Compression_Choice is
      GZip_Q    : Natural;
      Deflate_Q : Natural;
   begin
      if not Server_Config.Enable_Compression then
         return No_Compression;
      end if;

      GZip_Q := Response_Encoding_Q (Request, "gzip");
      Deflate_Q := Response_Encoding_Q (Request, "deflate");

      if GZip_Q = 0 and then Deflate_Q = 0 then
         return No_Compression;
      end if;

      if GZip_Q >= Deflate_Q then
         return GZip_Compression;
      end if;

      return Deflate_Compression;
   end Response_Compression;

   function Is_Valid_Registration_Path (Path : String) return Boolean is
   begin
      return Path'Length > 0
        and then Path (Path'First) = '/'
        and then Web.Security.Is_Safe_Path (Path)
        and then Index (Path, "?") = 0
        and then Index (Path, "#") = 0;
   end Is_Valid_Registration_Path;

   procedure Require_Registration_Path (Path : String; Name : String) is
   begin
      if not Is_Valid_Registration_Path (Path) then
         raise Web.Errors.Security_Error with "invalid " & Name & " path";
      end if;
   end Require_Registration_Path;

   procedure Reject_Unsupported_HTTP (Data : String) is
      Header_End   : constant Natural := Index (Data, CRLF & CRLF);
      Header       : constant String :=
        (if Header_End = 0 then Data else Data (Data'First .. Header_End - 1));
      Lower_Header : constant String := Ada.Characters.Handling.To_Lower (Header);
   begin
      if Data'Length > Server_Config.Max_Request_Size then
         raise Web.Errors.Bad_Request_Error with "request too large";
      end if;

      if Data'Length >= 14 and then Data (Data'First .. Data'First + 13) = "PRI * HTTP/2.0" then
         raise Web.Errors.Bad_Request_Error with "http/2 is not supported";
      end if;

      if Index (Header, " HTTP/1.1") = 0 then
         raise Web.Errors.Bad_Request_Error with "only HTTP/1.1 is supported";
      end if;

      if Has_Header_Token (Data, "Transfer-Encoding", "chunked") then
         raise Web.Errors.Bad_Request_Error with "chunked encoding is not supported";
      end if;

      if Header_Value (Data, "Content-Encoding")'Length > 0 then
         raise Web.Errors.Bad_Request_Error with "content encoding is not supported";
      end if;

      if Has_Header_Token (Data, "Content-Type", "multipart/form-data") then
         raise Web.Errors.Bad_Request_Error with "multipart uploads are not supported";
      end if;

      if Index (Lower_Header, CRLF & "expect:") > 0 then
         raise Web.Errors.Bad_Request_Error with "expect/continue is not supported";
      end if;
   end Reject_Unsupported_HTTP;

   procedure Get (Path : String; Handler : Route_Handler) is
   begin
      Require_Registration_Path (Path, "route");
      if Handler = null then
         raise Web.Errors.Security_Error with "route handler is null";
      end if;
      if Routes.Contains (Path) then
         raise Web.Errors.Security_Error with "duplicate route path";
      end if;
      Routes.Insert (Path, Handler);
   end Get;

   procedure WebSocket (Path : String; Handler : WebSocket_Handler) is
   begin
      Require_Registration_Path (Path, "websocket");
      if Handler = null then
         raise Web.Errors.Security_Error with "websocket handler is null";
      end if;
      if Sockets.Contains (Path) then
         raise Web.Errors.Security_Error with "duplicate websocket path";
      end if;
      Sockets.Insert (Path, Handler);
   end WebSocket;

   procedure Static (Url_Prefix : String; Directory : String) is
   begin
      Require_Registration_Path (Url_Prefix, "static");
      if Directory'Length = 0 or else not Web.Security.Is_Safe_Path (Directory) then
         raise Web.Errors.Security_Error with "invalid static directory";
      end if;
      Static_Prefix := To_Unbounded_String (Url_Prefix);
      Static_Dir := To_Unbounded_String (Directory);
   end Static;

   procedure Stop is
      Socket : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
      Should_Wake : Boolean;
   begin
      Server_State.Request_Stop (Address, Should_Wake);
      if Should_Wake then
         begin
            GNAT.Sockets.Create_Socket (Socket);
            GNAT.Sockets.Connect_Socket (Socket, Address);
            GNAT.Sockets.Close_Socket (Socket);
         exception
            when others =>
               begin
                  GNAT.Sockets.Close_Socket (Socket);
               exception
                  when others =>
                     null;
               end;
         end;
      end if;
   end Stop;

   function Header_Content_Length (Data : String) return Natural;

   function Parse_Request (Data : String) return Web.Request.Request_Type is
      Line_End : Natural := Index (Data, CRLF);
      Space_1  : Natural;
      Space_2  : Natural;
      Target   : Unbounded_String;
      Method_Text : Unbounded_String;
      Version_Text : Unbounded_String;
      Query_Position : Natural;
      Request  : Web.Request.Request_Type;
      Cursor   : Natural;
      Next_End : Natural;
      Colon    : Natural;
      Body_Start : Natural;
      Body_Text  : Unbounded_String;
      Declared_Length : Natural;
   begin
      Reject_Unsupported_HTTP (Data);
      Declared_Length := Header_Content_Length (Data);

      if Line_End = 0 then
         raise Web.Errors.Bad_Request_Error with "missing request line";
      end if;

      Space_1 := Index (Data (Data'First .. Line_End - 1), " ");
      Space_2 := Index (Data (Space_1 + 1 .. Line_End - 1), " ");
      if Space_1 = 0 or else Space_2 = 0 then
         raise Web.Errors.Bad_Request_Error with "malformed request line";
      end if;

      Method_Text := To_Unbounded_String (Data (Data'First .. Space_1 - 1));
      Target := To_Unbounded_String (Data (Space_1 + 1 .. Space_2 - 1));
      Version_Text := To_Unbounded_String (Data (Space_2 + 1 .. Line_End - 1));
      if not Is_Method_Name (To_String (Method_Text)) then
         raise Web.Errors.Bad_Request_Error with "invalid method";
      end if;

      if To_String (Version_Text) /= "HTTP/1.1" then
         raise Web.Errors.Bad_Request_Error with "only HTTP/1.1 is supported";
      end if;

      if not Is_Request_Target (To_String (Target)) then
         raise Web.Errors.Bad_Request_Error with "invalid request target";
      end if;

      Query_Position := Index (To_String (Target), "?");
      Body_Start := Index (Data, CRLF & CRLF);
      if Body_Start > 0 and then Body_Start + 3 <= Data'Last then
         Body_Text := To_Unbounded_String (Data (Body_Start + 4 .. Data'Last));
      end if;

      if Declared_Length = 0
        and then Body_Start > 0
        and then Index (To_String (Body_Text), CRLF & CRLF) > 0
      then
         raise Web.Errors.Bad_Request_Error with "http pipelining is not supported";
      end if;

      if Declared_Length > 0 and then Length (Body_Text) /= Declared_Length then
         raise Web.Errors.Bad_Request_Error with "content-length does not match body";
      end if;

      if Query_Position = 0 then
         Request :=
           Web.Request.Create
             (Data (Data'First .. Space_1 - 1),
              To_String (Target),
              Body_Value => To_String (Body_Text));
      else
         declare
            Target_String : constant String := To_String (Target);
         begin
            Request :=
              Web.Request.Create
                (Data (Data'First .. Space_1 - 1),
                 Target_String (Target_String'First .. Query_Position - 1),
                 Target_String (Query_Position + 1 .. Target_String'Last),
                 To_String (Body_Text));
         end;
      end if;

      Cursor := Line_End + CRLF'Length;
      loop
         Next_End := Index (Data (Cursor .. Data'Last), CRLF);
         exit when Next_End = 0;
         exit when Next_End = Cursor;

         Colon := Index (Data (Cursor .. Next_End - 1), ":");
         if Colon = 0 then
            raise Web.Errors.Bad_Request_Error with "malformed header";
         end if;

         declare
            Header_Name_Raw : constant String := Data (Cursor .. Colon - 1);
            Header_Name     : constant String := Trim (Header_Name_Raw, Ada.Strings.Both);
            Header_Text     : constant String := Trim (Data (Colon + 1 .. Next_End - 1), Ada.Strings.Both);
         begin
            if Header_Name /= Header_Name_Raw or else not Is_Header_Name (Header_Name) then
               raise Web.Errors.Bad_Request_Error with "invalid header name";
            end if;

            if not Is_Header_Value (Header_Text) then
               raise Web.Errors.Bad_Request_Error with "invalid header value";
            end if;

            if Web.Request.Has_Header (Request, Header_Name) then
               raise Web.Errors.Bad_Request_Error with "duplicate header";
            end if;

            Web.Request.Set_Header (Request, Header_Name, Header_Text);
         end;
         Cursor := Next_End + CRLF'Length;
      end loop;

      if not Web.Request.Has_Header (Request, "Host") then
         raise Web.Errors.Bad_Request_Error with "missing host header";
      end if;

      return Request;
   end Parse_Request;

   function Dispatch (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Path : constant String := Web.Request.Path (Request);
      Prefix : constant String := To_String (Static_Prefix);
   begin
      if Web.Request.Method (Request) /= "GET" then
         return Web.Response.Bad_Request;
      end if;

      if Routes.Contains (Path) then
         return Routes.Element (Path) (Request);
      end if;

      if Prefix'Length > 0 and then Index (Path, Prefix) = Path'First then
         return Web.Static.Serve (Prefix, To_String (Static_Dir), Path);
      end if;

      return Web.Response.Not_Found;
   exception
      when Error : others =>
         return Web.Errors.To_Response (Error, Server_Config.Mode);
   end Dispatch;

   procedure Send_Response
     (Conn     : in out Web.Connection.Connection_Type;
      Request  : Web.Request.Request_Type;
      Response : Web.Response.Response_Type)
   is
      Outgoing : Web.Response.Response_Type := Response;
   begin
      if Web.Response.Content_Body (Response)'Length < Server_Config.Compression_Min_Size then
         if not Response_Is_Acceptable (Request, Response) then
            Web.Connection.Send_All (Conn, Web.Response.Serialize (Web.Response.Not_Acceptable));
            return;
         end if;

         Web.Connection.Send_All (Conn, Web.Response.Serialize (Response));
         return;
      end if;

      if not Web.Response.Is_Compressible (Response) then
         if not Response_Is_Acceptable (Request, Response) then
            Web.Connection.Send_All (Conn, Web.Response.Serialize (Web.Response.Not_Acceptable));
            return;
         end if;

         Web.Connection.Send_All (Conn, Web.Response.Serialize (Response));
         return;
      end if;

      case Response_Compression (Request) is
         when No_Compression =>
            null;
         when GZip_Compression =>
            Outgoing := Web.Response.Compressed (Response, Web.Response.GZip);
         when Deflate_Compression =>
            Outgoing := Web.Response.Compressed (Response, Web.Response.Deflate);
      end case;

      if not Response_Is_Acceptable (Request, Outgoing) then
         Outgoing := Web.Response.Not_Acceptable;
      end if;

      Web.Connection.Send_All (Conn, Web.Response.Serialize (Outgoing));
   exception
      when Error : others =>
         Web.Logging.Warn ("response compression disabled: " & Ada.Exceptions.Exception_Message (Error));
         if Response_Is_Acceptable (Request, Response) then
            Web.Connection.Send_All (Conn, Web.Response.Serialize (Response));
         else
            Web.Connection.Send_All (Conn, Web.Response.Serialize (Web.Response.Not_Acceptable));
         end if;
   end Send_Response;

   procedure Configure (Config : Web.Config.Config_Type) is
   begin
      if Config.Max_Request_Size = 0 then
         raise Web.Errors.Security_Error with "max request size must be positive";
      end if;

      Server_Config.Configure (Config);
   end Configure;

   function Header_Content_Length (Data : String) return Natural is
      Value : constant String := Header_Value (Data, "Content-Length");
   begin
      if Value'Length = 0 then
         return 0;
      end if;

      for Ch of Value loop
         if Ch not in '0' .. '9' then
            raise Web.Errors.Bad_Request_Error with "invalid content-length";
         end if;
      end loop;

      return Natural'Value (Value);
   exception
      when others =>
         raise Web.Errors.Bad_Request_Error with "invalid content-length";
   end Header_Content_Length;

   procedure Require_Allowed_Request (Request : Web.Request.Request_Type) is
      Allowed : constant String := Server_Config.Allowed_Host;
   begin
      if Allowed'Length > 0
        and then not Web.Security.Require_Allowed_Origin (Request, Allowed)
      then
         raise Web.Errors.Security_Error with "request host/origin is not allowed";
      end if;
   end Require_Allowed_Request;

   function Stream_Data_To_String
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset) return String
   is
      use type Ada.Streams.Stream_Element_Offset;

      Result : String (1 .. Natural (Last - Data'First + 1));
   begin
      for Offset in Result'Range loop
         Result (Offset) :=
           Character'Val (Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset - 1)));
      end loop;
      return Result;
   end Stream_Data_To_String;

   function Read_Request (Conn : in out Web.Connection.Connection_Type) return String is
      use type Ada.Streams.Stream_Element_Offset;

      Buffer         : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last           : Ada.Streams.Stream_Element_Offset;
      Data           : Unbounded_String;
      Header_End     : Natural;
      Content_Length : Natural := 0;
      Expected_Size  : Natural;
   begin
      loop
         Web.Connection.Receive (Conn, Buffer, Last);
         if Last < Buffer'First then
            raise Web.Errors.Bad_Request_Error with "client closed before request";
         end if;

         Append (Data, Stream_Data_To_String (Buffer, Last));
         if Length (Data) > Server_Config.Max_Request_Size then
            raise Web.Errors.Bad_Request_Error with "request too large";
         end if;

         declare
            Raw : constant String := To_String (Data);
         begin
            Header_End := Index (Raw, CRLF & CRLF);
            if Header_End > 0 then
               Reject_Unsupported_HTTP (Raw);
               Content_Length := Header_Content_Length (Raw);
               Expected_Size := Header_End + 3 + Content_Length;
               if Raw'Length >= Expected_Size then
                  if Raw'Length > Expected_Size then
                     declare
                        Remainder : constant String := Raw (Expected_Size + 1 .. Raw'Last);
                     begin
                        if Index (Remainder, CRLF & CRLF) > 0 then
                           raise Web.Errors.Bad_Request_Error with "http pipelining is not supported";
                        end if;
                     end;
                  end if;
                  return Raw (Raw'First .. Expected_Size);
               end if;
            end if;
         end;
      end loop;
   end Read_Request;

   function WebSocket_Handshake (Request : Web.Request.Request_Type) return String is
      Accept_Value : constant String :=
        Web.WebSocket.Accept_Key (Web.Request.Header (Request, "Sec-WebSocket-Key"));
   begin
      return "HTTP/1.1 101 Switching Protocols" & CRLF
        & "Upgrade: websocket" & CRLF
        & "Connection: Upgrade" & CRLF
        & "Sec-WebSocket-Accept: " & Accept_Value & CRLF
        & CRLF;
   end WebSocket_Handshake;

   procedure Handle_Connection
     (Socket  : GNAT.Sockets.Socket_Type;
      Use_TLS : Boolean) is
      Close_When_Done : Boolean := True;
      Conn : Web.Connection.Connection_Type;
   begin
      if Use_TLS then
         Web.Connection.Open_TLS
           (Conn,
            Socket,
            TLS_State.Accept_Connection (Socket));
      else
         Web.Connection.Open_Plain (Conn, Socket);
      end if;

      declare
         Raw     : constant String := Read_Request (Conn);
         Request : constant Web.Request.Request_Type := Parse_Request (Raw);
         Path    : constant String := Web.Request.Path (Request);
      begin
         Web.Logging.Info (Web.Request.Method (Request) & " " & Path);
         Require_Allowed_Request (Request);

         if Web.WebSocket.Is_Upgrade (Request) then
            if Sockets.Contains (Path) then
               Web.Connection.Send_All (Conn, WebSocket_Handshake (Request));
               Sockets.Element (Path) (Conn, Request);
            else
               Send_Response (Conn, Request, Web.Response.Not_Found);
            end if;
         else
            Send_Response (Conn, Request, Dispatch (Request));
         end if;
      exception
         when Error : Web.Errors.Bad_Request_Error | Web.Errors.Protocol_Error | Web.Errors.Security_Error =>
            Web.Logging.Warn (Ada.Exceptions.Exception_Message (Error));
            Web.Connection.Send_All (Conn, Web.Response.Serialize (Web.Response.Bad_Request));
         when Error : others =>
            Web.Logging.Error (Ada.Exceptions.Exception_Information (Error));
            Web.Connection.Send_All (Conn, Web.Response.Serialize (Web.Response.Internal_Server_Error));
      end;

      if Close_When_Done then
         Web.Connection.Close (Conn);
      end if;
   exception
      when others =>
         if Close_When_Done then
            GNAT.Sockets.Close_Socket (Socket);
         end if;
   end Handle_Connection;

   task type Connection_Task is
      entry Start
        (Socket  : GNAT.Sockets.Socket_Type;
         Use_TLS : Boolean);
   end Connection_Task;

   task body Connection_Task is
      Client : GNAT.Sockets.Socket_Type;
      TLS_Client : Boolean;
   begin
      accept Start
        (Socket  : GNAT.Sockets.Socket_Type;
         Use_TLS : Boolean) do
         Client := Socket;
         TLS_Client := Use_TLS;
      end Start;

      Handle_Connection (Client, TLS_Client);
   end Connection_Task;

   type Connection_Task_Access is access Connection_Task;

   procedure Run_Internal
     (Host    : String;
      Port    : Natural;
      Use_TLS : Boolean) is
      Listener : GNAT.Sockets.Socket_Type;
      Address  : GNAT.Sockets.Sock_Addr_Type;
   begin
      GNAT.Sockets.Initialize;
      GNAT.Sockets.Create_Socket (Listener);
      Address.Addr := GNAT.Sockets.Inet_Addr (Host);
      Address.Port := GNAT.Sockets.Port_Type (Port);
      GNAT.Sockets.Bind_Socket (Listener, Address);
      GNAT.Sockets.Listen_Socket (Listener);
      Server_State.Started (Listener, Address);
      Web.Logging.Info
        ("listening on "
         & (if Use_TLS then "https://" else "http://")
         & Host
         & ":"
         & Trimmed_Image (Port));

      loop
         declare
            Socket : GNAT.Sockets.Socket_Type;
            Peer   : GNAT.Sockets.Sock_Addr_Type;
         begin
            GNAT.Sockets.Accept_Socket (Listener, Socket, Peer);
            if Server_State.Stopping then
               GNAT.Sockets.Close_Socket (Socket);
               exit;
            else
               declare
                  Worker : constant Connection_Task_Access := new Connection_Task;
               begin
                  Worker.Start (Socket, Use_TLS);
               end;
            end if;
         exception
            when Error : others =>
               if Server_State.Stopping then
                  exit;
               end if;
         Web.Logging.Error (Ada.Exceptions.Exception_Information (Error));
         end;
      end loop;
      Server_State.Finished;
   exception
      when others =>
         Server_State.Finished;
         raise;
   end Run_Internal;

   procedure Run (Host : String; Port : Natural) is
   begin
      Run_Internal (Host, Port, False);
   end Run;

   procedure Run_TLS
     (Host             : String;
      Port             : Natural;
      Certificate_File : String;
      Private_Key_File : String)
   is
   begin
      Run_TLS
        (Host,
         Port,
         Web.TLS.Configure_Server
           (Certificate_File => Certificate_File,
            Private_Key_File => Private_Key_File));
   end Run_TLS;

   procedure Run_TLS
     (Host       : String;
      Port       : Natural;
      TLS_Config : Web.TLS.Server_Config) is
   begin
      TLS_State.Initialize (TLS_Config);
      begin
         Run_Internal (Host, Port, True);
      exception
         when others =>
            TLS_State.Finalize;
            raise;
      end;
      TLS_State.Finalize;
   end Run_TLS;

   procedure Run_TLS
     (Host   : String;
      Port   : Natural;
      Config : Web.Config.Config_Type) is
   begin
      Run_TLS (Host, Port, Web.Config.TLS_Config (Config));
   end Run_TLS;

   procedure Reload_TLS (TLS_Config : Web.TLS.Server_Config) is
   begin
      TLS_State.Reload (TLS_Config);
   end Reload_TLS;
end Web.Server;
