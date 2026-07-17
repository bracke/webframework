with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Characters.Handling;
with Ada.Calendar;
with Ada.Exceptions;
with Ada.Streams;
   with Ada.Streams.Stream_IO;
   with Ada.Strings.Fixed;
   with Ada.Strings.Hash;
   with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
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
   use type Web.Config.Mode_Type;

   function Hash_Positive (Value : Positive) return Ada.Containers.Hash_Type is
      use Ada.Strings;
      Text : constant String := Trim (Positive'Image (Value), Both);
   begin
      return Ada.Strings.Hash (Text);
   end Hash_Positive;

   package Route_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => Route_Handler,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Socket_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => WebSocket_Handler,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Error_Handler_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => Positive,
      Element_Type => Error_Handler,
      Hash         => Hash_Positive,
      Equivalent_Keys => "=");

   type Compression_Choice is (No_Compression, GZip_Compression, Deflate_Compression);

   type Encoding_Negotiation is record
      GZip_Q     : Natural := 0;
      Deflate_Q  : Natural := 0;
      Identity_Q : Natural := 1000;
   end record;

   Routes : Route_Maps.Map;
   Sockets : Socket_Maps.Map;
   Static_Prefix : Unbounded_String;
   Static_Dir : Unbounded_String;
   Static_Prefix_Text : Unbounded_String;
   Static_Dir_Text : Unbounded_String;

   protected Error_Pages is
      procedure Register (Status : Positive; Handler : Error_Handler);
      procedure Clear (Status : Positive);
      function Handler (Status : Positive) return Error_Handler;
   private
      Handlers : Error_Handler_Maps.Map;
   end Error_Pages;

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
      function Running return Boolean;
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
      function Max_Connections return Natural;
      function Use_X_Forwarded_For return Boolean;
      function Enable_Compression return Boolean;
      function Compression_Min_Size return Natural;
      function Compression_Level return Natural;
      function Static_File_Buffer_Size return Natural;
   private
      Current_Mode : Web.Config.Mode_Type := Web.Config.Default_Config.Mode;
      Current_Allowed_Host : Unbounded_String :=
        To_Unbounded_String (Web.Config.Default_Config.Allowed_Host);
      Current_Max_Request_Size : Natural := Web.Config.Default_Config.Max_Request_Size;
      Current_Max_Connections : Natural := Web.Config.Default_Config.Max_Connections;
      Current_Use_X_Forwarded_For : Boolean :=
        Web.Config.Default_Config.Use_X_Forwarded_For;
      Current_Enable_Compression : Boolean := Web.Config.Default_Config.Enable_Compression;
      Current_Compression_Min_Size : Natural := Web.Config.Default_Config.Compression_Min_Size;
      Current_Compression_Level : Natural := Web.Config.Default_Config.Compression_Level;
      Current_Static_File_Buffer_Size : Natural := Web.Config.Default_Config.Static_File_Buffer_Size;
   end Server_Config;

   protected Connection_Limiter is
      procedure Try_Acquire (Accepted : out Boolean);
      procedure Release;
      function Active return Natural;
   private
      Active_Count : Natural := 0;
   end Connection_Limiter;

   protected Request_Ids is
      procedure Next (Id : out Natural);
   private
      Last_Id : Natural := 0;
   end Request_Ids;

   type Connection_Job is record
      Socket  : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Use_TLS : Boolean := False;
   end record;

   type Connection_Job_Array is array (Positive range <>) of Connection_Job;

   protected type Connection_Queue (Capacity : Positive) is
      procedure Enqueue
        (Socket  : GNAT.Sockets.Socket_Type;
         Use_TLS : Boolean);
      entry Dequeue
        (Socket  : out GNAT.Sockets.Socket_Type;
         Use_TLS : out Boolean;
         Has_Job : out Boolean);
      procedure Close;
   private
      Items  : Connection_Job_Array (1 .. Capacity);
      Head   : Positive := 1;
      Tail   : Positive := 1;
      Count  : Natural := 0;
      Closed : Boolean := False;
   end Connection_Queue;

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

      function Running return Boolean is
      begin
         return Listener /= GNAT.Sockets.No_Socket and then not Stop_Requested;
      end Running;
   end Server_State;

   protected body Server_Config is
      procedure Configure (Config : Web.Config.Config_Type) is
      begin
         Current_Mode := Config.Mode;
         Current_Allowed_Host := To_Unbounded_String (Trim (Config.Allowed_Host, Ada.Strings.Both));
         Current_Max_Request_Size := Config.Max_Request_Size;
         Current_Max_Connections := Config.Max_Connections;
         Current_Use_X_Forwarded_For := Config.Use_X_Forwarded_For;
         Current_Enable_Compression := Config.Enable_Compression;
         Current_Compression_Min_Size := Config.Compression_Min_Size;
         Current_Compression_Level := Config.Compression_Level;
         Current_Static_File_Buffer_Size := Config.Static_File_Buffer_Size;
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

      function Max_Connections return Natural is
      begin
         return Current_Max_Connections;
      end Max_Connections;

      function Use_X_Forwarded_For return Boolean is
      begin
         return Current_Use_X_Forwarded_For;
      end Use_X_Forwarded_For;

      function Enable_Compression return Boolean is
      begin
         return Current_Enable_Compression;
      end Enable_Compression;

      function Compression_Min_Size return Natural is
      begin
         return Current_Compression_Min_Size;
      end Compression_Min_Size;

      function Compression_Level return Natural is
      begin
         return Current_Compression_Level;
      end Compression_Level;

      function Static_File_Buffer_Size return Natural is
      begin
         return Current_Static_File_Buffer_Size;
      end Static_File_Buffer_Size;
   end Server_Config;

   protected body Connection_Limiter is
      procedure Try_Acquire (Accepted : out Boolean) is
      begin
         if Active_Count >= Server_Config.Max_Connections then
            Accepted := False;
            return;
         end if;

         Active_Count := Active_Count + 1;
         Accepted := True;
      end Try_Acquire;

      procedure Release is
      begin
         if Active_Count > 0 then
            Active_Count := Active_Count - 1;
         end if;
      end Release;

      function Active return Natural is
      begin
         return Active_Count;
      end Active;
   end Connection_Limiter;

   protected body Request_Ids is
      procedure Next (Id : out Natural) is
      begin
         if Last_Id = Natural'Last then
            Last_Id := 0;
         else
            Last_Id := Last_Id + 1;
         end if;

         Id := Last_Id;
      end Next;
   end Request_Ids;

   function Status_Text (Status : Positive) return String is
   begin
      case Status is
         when 400 =>
            return "Bad request";
         when 404 =>
            return "Not found";
         when 500 =>
            return "Internal server error";
         when others =>
            return "Error";
      end case;
   end Status_Text;

   function Default_Error_Response
     (Status : Positive;
      Detail : String) return Web.Response.Response_Type
   is
   begin
      if Detail'Length > 0 then
         return Web.Response.Create (Status, Detail, "text/plain; charset=utf-8");
      end if;

      if Status = 404 then
         return Web.Response.Not_Found;
      elsif Status = 400 then
         return Web.Response.Bad_Request;
      elsif Status = 500 then
         return Web.Response.Internal_Server_Error;
      end if;

      return
        Web.Response.Create (Status, Status_Text (Status), "text/plain; charset=utf-8");
   end Default_Error_Response;

   function Visible_Detail
     (Mode   : Web.Config.Mode_Type;
      Detail : String) return String
   is
   begin
      if Mode = Web.Config.Development then
         return Detail;
      end if;

      return "";
   end Visible_Detail;

   function Resolve_Error_Handler
     (Status : Positive) return Error_Handler
   is
      Handler : constant Error_Handler := Error_Pages.Handler (Status);
   begin
      return Handler;
   end Resolve_Error_Handler;

   function Build_Error_Response
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type
   is
      Handler : constant Error_Handler := Resolve_Error_Handler (Status);
   begin
      if Handler /= null then
         return Handler (Request, Status, Detail);
      end if;

      return Default_Error_Response (Status, Detail);
   exception
      when Error : others =>
         Web.Logging.Error (Ada.Exceptions.Exception_Message (Error));
         return Default_Error_Response (Status, "");
   end Build_Error_Response;

   function Build_Error_Response
     (Request : Web.Request.Request_Type;
      Error   : Ada.Exceptions.Exception_Occurrence) return Web.Response.Response_Type
   is
      Response : constant Web.Response.Response_Type :=
        Web.Errors.To_Response (Error, Server_Config.Mode);
      Status   : constant Positive := Web.Response.Status (Response);
      Detail   : constant String := Visible_Detail (Server_Config.Mode, Ada.Exceptions.Exception_Message (Error));
   begin
      return Build_Error_Response (Request, Status, Detail);
   end Build_Error_Response;

   protected body Error_Pages is
      procedure Register (Status : Positive; Handler : Error_Handler) is
      begin
         if Status < 100 or else Status > 599 then
            raise Web.Errors.Security_Error with "invalid error status code";
         end if;

         Handlers.Include (Status, Handler);
      end Register;

      procedure Clear (Status : Positive) is
      begin
         if Status < 100 or else Status > 599 then
            raise Web.Errors.Security_Error with "invalid error status code";
         end if;

         if Handlers.Contains (Status) then
            Handlers.Exclude (Status);
         end if;
      end Clear;

      function Handler (Status : Positive) return Error_Handler is
         Cursor : constant Error_Handler_Maps.Cursor := Handlers.Find (Status);
      begin
         if Error_Handler_Maps.Has_Element (Cursor) then
            return Error_Handler_Maps.Element (Cursor);
         end if;

         return null;
      end Handler;
   end Error_Pages;

   protected body Connection_Queue is
      procedure Enqueue
        (Socket  : GNAT.Sockets.Socket_Type;
         Use_TLS : Boolean)
      is
      begin
         if Closed then
            raise Web.Errors.Protocol_Error with "connection queue is closed";
         end if;

         if Count >= Capacity then
            raise Web.Errors.Protocol_Error with "connection queue is full";
         end if;

         Items (Tail) := (Socket => Socket, Use_TLS => Use_TLS);
         if Tail = Capacity then
            Tail := 1;
         else
            Tail := Tail + 1;
         end if;
         Count := Count + 1;
      end Enqueue;

      entry Dequeue
        (Socket  : out GNAT.Sockets.Socket_Type;
         Use_TLS : out Boolean;
         Has_Job : out Boolean) when Count > 0 or else Closed
      is
         Item : Connection_Job;
      begin
         if Count = 0 then
            Socket := GNAT.Sockets.No_Socket;
            Use_TLS := False;
            Has_Job := False;
            return;
         end if;

         Item := Items (Head);
         if Head = Capacity then
            Head := 1;
         else
            Head := Head + 1;
         end if;
         Count := Count - 1;

         Socket := Item.Socket;
         Use_TLS := Item.Use_TLS;
         Has_Job := True;
      end Dequeue;

      procedure Close is
      begin
         Closed := True;
      end Close;
   end Connection_Queue;

   function Trimmed_Image (Value : Natural) return String is
   begin
      return Trim (Natural'Image (Value), Ada.Strings.Both);
   end Trimmed_Image;

   function Two_Digit_Text (Value : Natural) return String is
   begin
      if Value < 10 then
         return "0" & Trim (Natural'Image (Value), Ada.Strings.Both);
      end if;

      return Trim (Natural'Image (Value), Ada.Strings.Both);
   end Two_Digit_Text;

   function Request_Timestamp (At_Time : Ada.Calendar.Time) return String is
      Year          : Ada.Calendar.Year_Number;
      Month         : Ada.Calendar.Month_Number;
      Day           : Ada.Calendar.Day_Number;
      Day_Seconds   : Duration;
      Total_Seconds : Natural;
      Hour_Value    : Natural;
      Minute_Value  : Natural;
      Second_Value  : Natural;
   begin
      Ada.Calendar.Split (At_Time, Year, Month, Day, Day_Seconds);

      Total_Seconds := Natural (Day_Seconds);
      Hour_Value := Total_Seconds / 3_600;
      Minute_Value := (Total_Seconds mod 3_600) / 60;
      Second_Value := Total_Seconds mod 60;

      return Trim (Integer'Image (Integer (Year)), Ada.Strings.Both)
        & "-"
        & Two_Digit_Text (Natural (Month))
        & "-"
        & Two_Digit_Text (Natural (Day))
        & "T"
        & Two_Digit_Text (Hour_Value)
        & ":"
        & Two_Digit_Text (Minute_Value)
        & ":"
        & Two_Digit_Text (Second_Value)
        & "Z";
   end Request_Timestamp;

   procedure Log_Request
     (Request_Id : Natural;
      Client_Ip  : String;
      Method     : String;
      Path       : String;
      Status     : Natural;
      At_Time    : String) is
   begin
      if Web.Logging.Enabled (Web.Logging.Info_Level) then
         Web.Logging.Info
           ("request_id=" & Trimmed_Image (Request_Id)
            & " ip=" & Client_Ip
            & " method=" & Method
            & " path=" & Path
            & " status=" & Trimmed_Image (Status)
            & " datetime=" & At_Time);
      end if;
   end Log_Request;

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
         if Character'Pos (Ch) < 32
           or else Character'Pos (Ch) = 127
           or else (Character'Pos (Ch) >= 128 and then Character'Pos (Ch) <= 159)
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
         return Web.Security.Is_Safe_Path (Value)
           and then Web.Security.Is_Safe_Decoded_Path (Value);
      end if;

      return Query_Position > Value'First
        and then Web.Security.Is_Safe_Path (Value (Value'First .. Query_Position - 1))
        and then Web.Security.Is_Safe_Decoded_Path (Value (Value'First .. Query_Position - 1));
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

   function Has_Header (Data : String; Name : String) return Boolean is
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
               return True;
            end if;
         end;

         exit when Line_End > Header'Last;
         Cursor := Line_End + CRLF'Length;
      end loop;

      return False;
   end Has_Header;

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
            Param_Pos : constant Natural := Index (Item, ";");
            Name_Text : constant String :=
              (if Param_Pos = 0
               then Item
               else Trim (Item (Item'First .. Param_Pos - 1), Ada.Strings.Both));
         begin
            if Name_Text = Lower_Token then
               return True;
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      return False;
   end Has_Header_Token;

   function Header_Text_Has_Token (Value : String; Token : String) return Boolean is
      Lower_Value : constant String := Ada.Characters.Handling.To_Lower (Value);
      Lower_Token : constant String := Ada.Characters.Handling.To_Lower (Token);
      Start_Pos   : Natural := Lower_Value'First;
      Comma_Pos   : Natural;
   begin
      if Lower_Value'Length = 0 then
         return False;
      end if;

      loop
         Comma_Pos := Index (Lower_Value (Start_Pos .. Lower_Value'Last), ",");
         declare
            Last_Pos : constant Natural :=
              (if Comma_Pos = 0 then Lower_Value'Last else Comma_Pos - 1);
            Item     : constant String := Trim (Lower_Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
            Param_Pos : constant Natural := Index (Item, ";");
            Name_Text : constant String :=
              (if Param_Pos = 0
               then Item
               else Trim (Item (Item'First .. Param_Pos - 1), Ada.Strings.Both));
         begin
            if Name_Text = Lower_Token then
               return True;
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      return False;
   end Header_Text_Has_Token;

   function Equals_Case_Insensitive (Left : String; Right : String) return Boolean is
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;

      for Offset in 0 .. Left'Length - 1 loop
         if Ada.Characters.Handling.To_Lower (Left (Left'First + Offset))
           /= Ada.Characters.Handling.To_Lower (Right (Right'First + Offset))
         then
            return False;
         end if;
      end loop;

      return True;
   end Equals_Case_Insensitive;

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
        Ada.Characters.Handling.To_Lower
          (Web.Request.Header (Request, Web.Request.Accept_Encoding_Header));
      Lower_Token : constant String := Ada.Characters.Handling.To_Lower (Token);
      Start_Pos   : Natural := Value'First;
      Comma_Pos   : Natural;
      Explicit     : Boolean := False;
      Explicit_Q   : Natural := 0;
      Wildcard     : Boolean := False;
      Wildcard_Q   : Natural := 0;
   begin
      if not Web.Request.Has_Header (Request, Web.Request.Accept_Encoding_Header) then
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
            if Item'Length = 0 or else Name'Length = 0 or else not Is_Header_Name (Name) then
               return 0;
            end if;

            if Name = Lower_Token then
               if Explicit then
                  return 0;
               end if;
               Explicit := True;
               Explicit_Q := Q_Value (Parameters);
            elsif Name = "*" then
               if Wildcard then
                  return 0;
               end if;
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

   function Parse_Accept_Encoding (Request : Web.Request.Request_Type) return Encoding_Negotiation is
      Accept_Encoding : constant String :=
        Web.Request.Header (Request, Web.Request.Accept_Encoding_Header);
      Result : Encoding_Negotiation;
   begin
      if Accept_Encoding'Length = 0 then
         return Result;
      end if;

      declare
         Value       : constant String := Accept_Encoding;
         Start_Pos   : Natural := Value'First;
         Comma_Pos   : Natural;
         Wildcard_Q  : Natural := 0;
         Has_Wildcard : Boolean := False;
         Has_GZip    : Boolean := False;
         Has_Deflate : Boolean := False;
         Has_Identity : Boolean := False;
      begin
         Result.Identity_Q := 1000;

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
               Q             : Natural;
            begin
               if Item'Length = 0 or else Name'Length = 0 or else not Is_Header_Name (Name) then
                  return (GZip_Q => 0, Deflate_Q => 0, Identity_Q => 0);
               end if;

               Q := Q_Value (Parameters);
               if Equals_Case_Insensitive (Name, "gzip") then
                  if Has_GZip then
                     return (GZip_Q => 0, Deflate_Q => 0, Identity_Q => 0);
                  end if;
                  Has_GZip := True;
                  Result.GZip_Q := Q;
               elsif Equals_Case_Insensitive (Name, "deflate") then
                  if Has_Deflate then
                     return (GZip_Q => 0, Deflate_Q => 0, Identity_Q => 0);
                  end if;
                  Has_Deflate := True;
                  Result.Deflate_Q := Q;
               elsif Equals_Case_Insensitive (Name, "identity") then
                  if Has_Identity then
                     return (GZip_Q => 0, Deflate_Q => 0, Identity_Q => 0);
                  end if;
                  Has_Identity := True;
                  Result.Identity_Q := Q;
               elsif Name = "*" then
                  if Has_Wildcard then
                     return (GZip_Q => 0, Deflate_Q => 0, Identity_Q => 0);
                  end if;
                  Has_Wildcard := True;
                  Wildcard_Q := Q;
               end if;
            end;

            exit when Comma_Pos = 0;
            Start_Pos := Comma_Pos + 1;
         end loop;

         if Has_Wildcard then
            if not Has_GZip then
               Result.GZip_Q := Wildcard_Q;
            end if;
            if not Has_Deflate then
               Result.Deflate_Q := Wildcard_Q;
            end if;
            if not Has_Identity then
               Result.Identity_Q := Wildcard_Q;
            end if;
         end if;

         return Result;
      end;
   end Parse_Accept_Encoding;

   function Encoding_Q
     (Negotiation : Encoding_Negotiation;
      Encoding    : String) return Natural
   is
   begin
      if Encoding = "" then
         return Negotiation.Identity_Q;
      elsif Encoding = "gzip" then
         return Negotiation.GZip_Q;
      elsif Encoding = "deflate" then
         return Negotiation.Deflate_Q;
      end if;

      return 0;
   end Encoding_Q;

   function Response_Is_Acceptable
     (Negotiation : Encoding_Negotiation;
      Response    : Web.Response.Response_Type) return Boolean
   is
   begin
      return Encoding_Q (Negotiation, Web.Response.Header (Response, "Content-Encoding")) > 0;
   end Response_Is_Acceptable;

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

   function Encoding_Not_Acceptable return Web.Response.Response_Type is
      Response : Web.Response.Response_Type := Web.Response.Not_Acceptable;
   begin
      Web.Response.Ensure_Vary (Response, "Accept-Encoding");
      return Response;
   end Encoding_Not_Acceptable;

   function Encoding_Varying
     (Response : Web.Response.Response_Type) return Web.Response.Response_Type
   is
      Result : Web.Response.Response_Type := Response;
   begin
      Web.Response.Ensure_Vary (Result, "Accept-Encoding");
      return Result;
   end Encoding_Varying;

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

   function Response_Compression (Negotiation : Encoding_Negotiation) return Compression_Choice is
   begin
      if not Server_Config.Enable_Compression then
         return No_Compression;
      end if;

      if Negotiation.GZip_Q = 0 and then Negotiation.Deflate_Q = 0 then
         return No_Compression;
      end if;

      if Negotiation.GZip_Q >= Negotiation.Deflate_Q then
         return GZip_Compression;
      end if;

      return Deflate_Compression;
   end Response_Compression;

   function Fallback_Response
     (Request  : Web.Request.Request_Type;
      Response : Web.Response.Response_Type) return Web.Response.Response_Type
   is
   begin
      if Response_Is_Acceptable (Request, Response) then
         return Encoding_Varying (Response);
      end if;

      return Encoding_Not_Acceptable;
   end Fallback_Response;

   function Fallback_Response
     (Negotiation : Encoding_Negotiation;
      Response    : Web.Response.Response_Type) return Web.Response.Response_Type
   is
   begin
      if Response_Is_Acceptable (Negotiation, Response) then
         return Encoding_Varying (Response);
      end if;

      return Encoding_Not_Acceptable;
   end Fallback_Response;

   function Prepared_Response
     (Request  : Web.Request.Request_Type;
      Response : Web.Response.Response_Type) return Web.Response.Response_Type
   is
      Outgoing : Web.Response.Response_Type := Response;
      Accept_Encoding_Header_Present : constant Boolean :=
        Web.Request.Has_Header (Request, Web.Request.Accept_Encoding_Header);
      Negotiation : constant Encoding_Negotiation :=
        (if Accept_Encoding_Header_Present
         then Parse_Accept_Encoding (Request)
         else (GZip_Q => 0, Deflate_Q => 0, Identity_Q => 1000));
   begin
      if not Web.Response.Is_Compressible (Response) then
         return Fallback_Response (Negotiation, Response);
      end if;

      if Web.Response.Body_Length (Response) < Server_Config.Compression_Min_Size
        and then Response_Is_Acceptable (Negotiation, Response)
      then
         return Encoding_Varying (Response);
      end if;

      case Response_Compression (Negotiation) is
         when No_Compression =>
            null;
         when GZip_Compression =>
            Outgoing :=
              Web.Response.Compressed
                (Response,
                 Web.Response.GZip,
                 Server_Config.Compression_Level);
         when Deflate_Compression =>
            Outgoing :=
              Web.Response.Compressed
                (Response,
                 Web.Response.Deflate,
                 Server_Config.Compression_Level);
      end case;

      return Fallback_Response (Negotiation, Outgoing);
   end Prepared_Response;

   function Is_Valid_Registration_Path (Path : String) return Boolean is
   begin
      return Path'Length > 0
        and then Path (Path'First) = '/'
        and then Web.Security.Is_Safe_Path (Path)
        and then Web.Security.Is_Safe_Decoded_Path (Path)
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
   begin
      if Data'Length > Server_Config.Max_Request_Size then
         raise Web.Errors.Bad_Request_Error with "request too large";
      end if;

      if Data'Length >= 14 and then Data (Data'First .. Data'First + 13) = "PRI * HTTP/2.0" then
         raise Web.Errors.Bad_Request_Error with "http/2 is not supported";
      end if;
   end Reject_Unsupported_HTTP;

   procedure Get (Path : String; Handler : Route_Handler) is
      Position : Route_Maps.Cursor;
      Inserted : Boolean;
   begin
      Require_Registration_Path (Path, "route");
      if Handler = null then
         raise Web.Errors.Security_Error with "route handler is null";
      end if;

      Route_Maps.Insert
        (Container => Routes,
         Key       => "GET " & Path,
         New_Item  => Handler,
         Position  => Position,
         Inserted  => Inserted);
      if not Inserted then
         raise Web.Errors.Security_Error with "duplicate route path";
      end if;
   end Get;

   procedure Post (Path : String; Handler : Route_Handler) is
      Position : Route_Maps.Cursor;
      Inserted : Boolean;
   begin
      Require_Registration_Path (Path, "route");
      if Handler = null then
         raise Web.Errors.Security_Error with "route handler is null";
      end if;

      Route_Maps.Insert
        (Container => Routes,
         Key       => "POST " & Path,
         New_Item  => Handler,
         Position  => Position,
         Inserted  => Inserted);
      if not Inserted then
         raise Web.Errors.Security_Error with "duplicate route path";
      end if;
   end Post;

   procedure WebSocket (Path : String; Handler : WebSocket_Handler) is
      Position : Socket_Maps.Cursor;
      Inserted : Boolean;
   begin
      Require_Registration_Path (Path, "websocket");
      if Handler = null then
         raise Web.Errors.Security_Error with "websocket handler is null";
      end if;

      Socket_Maps.Insert
        (Container => Sockets,
         Key       => Path,
         New_Item  => Handler,
         Position  => Position,
         Inserted  => Inserted);
      if not Inserted then
         raise Web.Errors.Security_Error with "duplicate websocket path";
      end if;
   end WebSocket;

   procedure Register_Error_Handler (Status : Positive; Handler : Error_Handler) is
   begin
      Error_Pages.Register (Status, Handler);
   end Register_Error_Handler;

   procedure Clear_Error_Handler (Status : Positive) is
   begin
      Error_Pages.Clear (Status);
   end Clear_Error_Handler;

   procedure Static (Url_Prefix : String; Directory : String) is
   begin
      Require_Registration_Path (Url_Prefix, "static");
      if Directory'Length = 0 or else not Web.Security.Is_Safe_Path (Directory) then
         raise Web.Errors.Security_Error with "invalid static directory";
      end if;
      Static_Prefix := To_Unbounded_String (Url_Prefix);
      Static_Dir := To_Unbounded_String (Directory);
      Static_Prefix_Text := To_Unbounded_String (Url_Prefix);
      Static_Dir_Text := To_Unbounded_String (Directory);
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

   function Running return Boolean is
   begin
      return Server_State.Running;
   end Running;

   procedure Require_Bind_Port (Port : Natural) is
   begin
      if Port = 0 or else Port > 65_535 then
         raise Web.Errors.Security_Error with "bind port must be in 1 .. 65535";
      end if;
   end Require_Bind_Port;

   procedure Require_Bind_Host (Host : String) is
   begin
      if Host'Length = 0 then
         raise Web.Errors.Security_Error with "bind host must not be empty";
      end if;

      for Ch of Host loop
         if Character'Pos (Ch) < 32
           or else Character'Pos (Ch) = 127
           or else (Character'Pos (Ch) >= 128 and then Character'Pos (Ch) <= 159)
         then
            raise Web.Errors.Security_Error with "bind host contains a control byte";
         end if;
      end loop;

      declare
         Ignored : GNAT.Sockets.Inet_Addr_Type;
      begin
         Ignored := GNAT.Sockets.Inet_Addr (Host);
         null;
      exception
         when others =>
            raise Web.Errors.Security_Error with "bind host must be a numeric address";
      end;
   end Require_Bind_Host;

   function Parse_Natural_Decimal (Text : String; Value : out Natural) return Boolean is
      Accumulator : Natural := 0;
   begin
      Value := 0;

      if Text'Length = 0 then
         return False;
      end if;

      for Ch of Text loop
         if Ch not in '0' .. '9' then
            return False;
         end if;

         declare
            Digit : constant Natural := Character'Pos (Ch) - Character'Pos ('0');
         begin
            if Accumulator > (Natural'Last - Digit) / 10 then
               return False;
            end if;

            Accumulator := Accumulator * 10 + Digit;
         end;
      end loop;

      Value := Accumulator;
      return True;
   end Parse_Natural_Decimal;

   function Trim_Header_Field (Text : String) return String is
      First : Natural := Text'First;
      Last : Natural := Text'Last;
   begin
      while First <= Last and then (Text (First) = ' ' or else Text (First) = Character'Val (9)) loop
         First := First + 1;
      end loop;

      while Last >= First and then (Text (Last) = ' ' or else Text (Last) = Character'Val (9)) loop
         Last := Last - 1;
      end loop;

      if First > Last then
         return "";
      end if;

      return Text (First .. Last);
   end Trim_Header_Field;
   pragma Inline (Trim_Header_Field);

   function Header_Content_Length (Data : String) return Natural;

   function Starts_Case_Insensitive (Value : String; Prefix : String) return Boolean is
   begin
      return Value'Length >= Prefix'Length
        and then Equals_Case_Insensitive
          (Value (Value'First .. Value'First + Prefix'Length - 1), Prefix);
   end Starts_Case_Insensitive;
   pragma Inline (Starts_Case_Insensitive);

   function Parse_Request (Data : String) return Web.Request.Request_Type is
      Line_End : Natural := Index (Data, CRLF);
      Space_1  : Natural;
      Space_2  : Natural;
      Query_Position : Natural;
      Request  : Web.Request.Request_Type;
      Cursor   : Natural;
      Next_End : Natural;
      Colon    : Natural;
      Body_Start : Natural;
      Body_First : Natural := 1;
      Body_Last  : Natural := 0;
      Declared_Length : Natural;
      Has_Header_Host : Boolean := False;
      Has_Header_Content_Length : Boolean := False;
   begin
      Reject_Unsupported_HTTP (Data);
      Declared_Length := 0;

      if Line_End = 0 then
         raise Web.Errors.Bad_Request_Error with "missing request line";
      end if;

      Space_1 := Index (Data (Data'First .. Line_End - 1), " ");
      Space_2 := Index (Data (Space_1 + 1 .. Line_End - 1), " ");
      if Space_1 = 0 or else Space_2 = 0 then
         raise Web.Errors.Bad_Request_Error with "malformed request line";
      end if;

      declare
         Method_Text  : constant String := Data (Data'First .. Space_1 - 1);
         Target_Text  : constant String := Data (Space_1 + 1 .. Space_2 - 1);
         Version_Text : constant String := Data (Space_2 + 1 .. Line_End - 1);
      begin
         if not Is_Method_Name (Method_Text) then
            raise Web.Errors.Bad_Request_Error with "invalid method";
         end if;

         if Version_Text /= "HTTP/1.1" then
            raise Web.Errors.Bad_Request_Error with "only HTTP/1.1 is supported";
         end if;

         if not Is_Request_Target (Target_Text) then
            raise Web.Errors.Bad_Request_Error with "invalid request target";
         end if;

         Query_Position := Index (Target_Text, "?");
         Body_Start := Index (Data, CRLF & CRLF);
         if Body_Start > 0 and then Body_Start + 3 <= Data'Last then
            Body_First := Body_Start + 4;
            Body_Last := Data'Last;
         end if;

         declare
            Body_Value : constant String :=
              (if Body_First <= Body_Last then Data (Body_First .. Body_Last) else "");
         begin
            if Query_Position = 0 then
               Request :=
                 Web.Request.Create
                   (Method_Text,
                    Target_Text,
                    Body_Value => Body_Value);
            else
               Request :=
                 Web.Request.Create
                   (Method_Text,
                    Target_Text (Target_Text'First .. Query_Position - 1),
                    Target_Text (Query_Position + 1 .. Target_Text'Last),
                    Body_Value);
            end if;
         end;
      end;

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
            Header_Text     : constant String :=
              Trim_Header_Field
                (if Colon + 1 <= Next_End - 1
                 then Data (Colon + 1 .. Next_End - 1)
                 else "");
            Header_Kind_Value : Web.Request.Header_Kind;
         begin
            if not Is_Header_Name (Header_Name_Raw) then
               raise Web.Errors.Bad_Request_Error with "invalid header name";
            end if;

            Header_Kind_Value := Web.Request.Header_Kind_Of (Header_Name_Raw);
            if not Is_Header_Value (Header_Text) then
                raise Web.Errors.Bad_Request_Error with "invalid header value";
            end if;

            case Header_Kind_Value is
               when Web.Request.Host_Header =>
                  if Header_Text'Length = 0 then
                     raise Web.Errors.Bad_Request_Error with "empty host header";
                  end if;
                  if Web.Security.Normalize_Authority (Header_Text)'Length = 0 then
                     raise Web.Errors.Bad_Request_Error with "invalid host header";
                  end if;
                  Has_Header_Host := True;
               when Web.Request.Content_Type_Header =>
                  if Header_Text_Has_Token (Header_Text, "multipart/form-data") then
                     raise Web.Errors.Bad_Request_Error with "multipart uploads are not supported";
                  end if;
               when Web.Request.Content_Length_Header =>
                  Has_Header_Content_Length := True;
                  if not Parse_Natural_Decimal (Header_Text, Declared_Length) then
                     raise Web.Errors.Bad_Request_Error with "invalid content-length";
                  end if;
               when Web.Request.Transfer_Encoding_Header =>
                  raise Web.Errors.Bad_Request_Error with
                    "transfer encoding is not supported";
               when Web.Request.Content_Encoding_Header =>
                  raise Web.Errors.Bad_Request_Error with "content encoding is not supported";
               when Web.Request.Expect_Header =>
                  raise Web.Errors.Bad_Request_Error with "expect/continue is not supported";
               when Web.Request.Unknown_Header =>
                  null;
               when others =>
                  null;
            end case;

            if not Web.Request.Add_Validated_Header
              (Request, Header_Kind_Value, Header_Name_Raw, Header_Text)
            then
               raise Web.Errors.Bad_Request_Error with "duplicate header";
            end if;

         end;
         Cursor := Next_End + CRLF'Length;
      end loop;

      if not Has_Header_Content_Length and then Body_First <= Body_Last then
         if Index (Data (Body_First .. Body_Last), CRLF & CRLF) > 0 then
            raise Web.Errors.Bad_Request_Error with "http pipelining is not supported";
         end if;

         raise Web.Errors.Bad_Request_Error with "unexpected request body";
      end if;

      if Has_Header_Content_Length
        and then (if Body_First <= Body_Last then Body_Last - Body_First + 1 else 0)
         /= Declared_Length
      then
         raise Web.Errors.Bad_Request_Error with "content-length does not match body";
      end if;

      if not Has_Header_Host then
         raise Web.Errors.Bad_Request_Error with "missing host header";
      end if;

      if Web.Request.Method (Request) = "POST" and then not Has_Header_Content_Length then
         raise Web.Errors.Bad_Request_Error with "post requires content-length";
      end if;

      return Request;
   end Parse_Request;

   function Static_Prefix_Matches (Path : String) return Boolean is
      Prefix_Length : constant Natural := Length (Static_Prefix_Text);
   begin
      if Prefix_Length = 0 or else Path'Length < Prefix_Length then
         return False;
      end if;

      for Offset in 0 .. Prefix_Length - 1 loop
         if Path (Path'First + Offset) /= Element (Static_Prefix_Text, Offset + 1) then
            return False;
         end if;
      end loop;

      return True;
   end Static_Prefix_Matches;

   function Dispatch (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Method : constant String := Web.Request.Method (Request);
      Path : constant String := Web.Request.Path (Request);
      Route_Key : constant String := Method & " " & Path;
   begin
      --  Only allow GET and POST methods
      if Method /= "GET" and Method /= "POST" then
         return Build_Error_Response (Request, 405, "method not allowed");
      end if;

      declare
         Cursor : constant Route_Maps.Cursor := Routes.Find (Route_Key);
      begin
         if Route_Maps.Has_Element (Cursor) then
            return Route_Maps.Element (Cursor) (Request);
         end if;

         --  Static files are only served via GET
         if Method = "GET" and Static_Prefix_Matches (Path) then
            return Web.Static.Serve (To_String (Static_Prefix_Text), To_String (Static_Dir_Text), Path);
         end if;
      end;

      --  A POST that matches no registered route is a bad request: this
      --  framework is GET/WebSocket-driven, so POST is only valid against an
      --  explicitly registered route. An unmatched GET is a normal 404.
      if Method = "POST" then
         return Build_Error_Response (Request, 400, "");
      end if;

      return Build_Error_Response (Request, 404, "");
   exception
      when Error : others =>
         return Build_Error_Response (Request, Error);
   end Dispatch;

   procedure Send_Buffer_All
     (Conn   : in out Web.Connection.Connection_Type;
      Buffer : Ada.Streams.Stream_Element_Array)
   is
      use type Ada.Streams.Stream_Element_Offset;

      First     : Ada.Streams.Stream_Element_Offset := Buffer'First;
      Last_Sent : Ada.Streams.Stream_Element_Offset;
   begin
      while First <= Buffer'Last loop
         Web.Connection.Send (Conn, Buffer (First .. Buffer'Last), Last_Sent);
         if Last_Sent < First then
            raise Web.Errors.Protocol_Error with "connection send failed";
         end if;
         First := Last_Sent + 1;
      end loop;
   end Send_Buffer_All;

   procedure Send_File_Body
     (Conn     : in out Web.Connection.Connection_Type;
      Response : Web.Response.Response_Type)
   is
      use type Ada.Streams.Stream_Element_Offset;

      File        : Ada.Streams.Stream_IO.File_Type;
      Buffer_Size : constant Natural := Server_Config.Static_File_Buffer_Size;
      Buffer      : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Buffer_Size));
      Last        : Ada.Streams.Stream_Element_Offset;
   begin
      Ada.Streams.Stream_IO.Open
        (File,
         Ada.Streams.Stream_IO.In_File,
         Web.Response.File_Body_Path (Response));

      while not Ada.Streams.Stream_IO.End_Of_File (File) loop
         Ada.Streams.Stream_IO.Read (File, Buffer, Last);
         if Last >= Buffer'First then
            Send_Buffer_All (Conn, Buffer (Buffer'First .. Last));
         end if;
      end loop;

      Ada.Streams.Stream_IO.Close (File);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Send_File_Body;

   procedure Send_Response
     (Conn     : in out Web.Connection.Connection_Type;
      Request  : Web.Request.Request_Type;
      Response : Web.Response.Response_Type)
   is
      Prepared : constant Web.Response.Response_Type :=
        Prepared_Response (Request, Response);
   begin
      Web.Connection.Send_All (Conn, Web.Response.Serialize (Prepared));
      if Web.Response.Is_File_Body (Prepared) then
         Send_File_Body (Conn, Prepared);
      end if;
   exception
      when Error : others =>
         declare
            Fallback : constant Web.Response.Response_Type :=
              Fallback_Response (Request, Response);
         begin
            Web.Logging.Warn ("response compression disabled: " & Ada.Exceptions.Exception_Message (Error));
            Web.Connection.Send_All (Conn, Web.Response.Serialize (Fallback));
            if Web.Response.Is_File_Body (Fallback) then
               Send_File_Body (Conn, Fallback);
            end if;
         end;
   end Send_Response;

   procedure Configure (Config : Web.Config.Config_Type) is
      Allowed : constant String := Trim (Config.Allowed_Host, Ada.Strings.Both);
   begin
      if Config.Max_Request_Size = 0 then
         raise Web.Errors.Security_Error with "max request size must be positive";
      end if;

      if Config.Max_Connections = 0 then
         raise Web.Errors.Security_Error with "max connections must be positive";
      end if;

      if Config.Compression_Level > 9 then
         raise Web.Errors.Security_Error with "compression level must be in 0 .. 9";
      end if;

      if Config.Static_File_Buffer_Size = 0 then
         raise Web.Errors.Security_Error with "static file buffer size must be positive";
      end if;

      if Allowed'Length > 0
        and then Web.Security.Normalize_Authority (Allowed)'Length = 0
        and then Web.Security.Normalize_Origin (Allowed)'Length = 0
      then
         raise Web.Errors.Security_Error with "allowed host is invalid";
      end if;

      Server_Config.Configure (Config);
   end Configure;

   function Health_Response return Web.Response.Response_Type is
   begin
      return Web.Response.Text ("ok");
   end Health_Response;

   function Configuration_Report return String is
   begin
      return "mode="
        & (if Server_Config.Mode = Web.Config.Production then "production" else "development")
        & " allowed_host="
        & Server_Config.Allowed_Host
        & " use_x_forwarded_for="
        & (if Server_Config.Use_X_Forwarded_For then "enabled" else "disabled")
        & " max_request_size="
        & Trimmed_Image (Server_Config.Max_Request_Size)
        & " max_connections="
        & Trimmed_Image (Server_Config.Max_Connections)
        & " compression="
        & (if Server_Config.Enable_Compression then "enabled" else "disabled")
        & " compression_min_size="
        & Trimmed_Image (Server_Config.Compression_Min_Size)
        & " compression_level="
        & Trimmed_Image (Server_Config.Compression_Level)
        & " static_file_buffer_size="
        & Trimmed_Image (Server_Config.Static_File_Buffer_Size)
        & " active_connections="
        & Trimmed_Image (Connection_Limiter.Active);
   end Configuration_Report;

   function Header_Content_Length (Data : String) return Natural is
      Header_End : constant Natural := Index (Data, CRLF & CRLF);
      Header     : constant String :=
        (if Header_End = 0 then Data else Data (Data'First .. Header_End - 1));
      Prefix     : constant String := "content-length:";
      Cursor     : Natural := Header'First;
      Line_End   : Natural;
      Found      : Boolean := False;
      Result     : Natural := 0;

      function Parse_Content_Length (Line : String) return Natural is
         Value      : Natural := 0;
         Cursor_Pos : Natural := Line'First + Prefix'Length;
         At_End     : constant Natural := Line'Last;

         function Is_Ows (Ch : Character) return Boolean is
         begin
            return Ch = ' ' or else Ch = Character'Val (9);
         end Is_Ows;
   begin
         while Cursor_Pos <= At_End and then Is_Ows (Line (Cursor_Pos)) loop
            Cursor_Pos := Cursor_Pos + 1;
         end loop;

         if Cursor_Pos > At_End then
            raise Web.Errors.Bad_Request_Error with "invalid content-length";
         end if;

         while Cursor_Pos <= At_End and then Line (Cursor_Pos) in '0' .. '9' loop
            declare
               Digit : constant Natural :=
                 Character'Pos (Line (Cursor_Pos)) - Character'Pos ('0');
            begin
               if Value > (Natural'Last - Digit) / 10 then
                  raise Web.Errors.Bad_Request_Error with "content-length overflow";
               end if;

               Value := Value * 10 + Digit;
            end;

            Cursor_Pos := Cursor_Pos + 1;
         end loop;

         if Cursor_Pos = Line'First + Prefix'Length then
            raise Web.Errors.Bad_Request_Error with "invalid content-length";
         end if;

         while Cursor_Pos <= At_End and then Is_Ows (Line (Cursor_Pos)) loop
            Cursor_Pos := Cursor_Pos + 1;
         end loop;

         if Cursor_Pos <= At_End then
            raise Web.Errors.Bad_Request_Error with "invalid content-length";
         end if;

         return Value;
      end Parse_Content_Length;
   begin
      loop
         Line_End := Index (Header (Cursor .. Header'Last), CRLF);
         if Line_End = 0 then
            Line_End := Header'Last + 1;
         end if;

         declare
            Line : constant String := Header (Cursor .. Line_End - 1);
         begin
            if Starts_Case_Insensitive (Line, Prefix) then
               if Found then
                  raise Web.Errors.Bad_Request_Error with "duplicate content-length";
               end if;

               Found := True;
               Result := Parse_Content_Length (Line);
               exit;
            end if;
         end;

         exit when Line_End > Header'Last;
         Cursor := Line_End + CRLF'Length;
      end loop;

      return (if Found then Result else 0);
   exception
      when others =>
         raise Web.Errors.Bad_Request_Error with "invalid content-length";
   end Header_Content_Length;

   function Header_End_Position (Data : Unbounded_String) return Natural is
      Size : constant Natural := Length (Data);
   begin
      if Size < 4 then
         return 0;
      end if;

      for Index_Value in 1 .. Size - 3 loop
         if Element (Data, Index_Value) = Character'Val (13)
           and then Element (Data, Index_Value + 1) = Character'Val (10)
           and then Element (Data, Index_Value + 2) = Character'Val (13)
           and then Element (Data, Index_Value + 3) = Character'Val (10)
         then
            return Index_Value;
         end if;
      end loop;

      return 0;
   end Header_End_Position;

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
      Max_Size       : constant Natural := Server_Config.Max_Request_Size;
      type Request_Buffer_Access is access String;
      procedure Free is new Ada.Unchecked_Deallocation (String, Request_Buffer_Access);
      Data           : Request_Buffer_Access := new String (1 .. Max_Size);
      Data_Length    : Natural := 0;
      Header_End     : Natural;
      Content_Length : Natural := 0;
      Expected_Size  : Natural := 0;
      Header_Parsed  : Boolean := False;

      function Find_Header_End return Natural is
      begin
         if Data_Length < 4 then
            return 0;
         end if;

         for Index_Value in 1 .. Data_Length - 3 loop
            if Data (Index_Value) = Character'Val (13)
              and then Data (Index_Value + 1) = Character'Val (10)
              and then Data (Index_Value + 2) = Character'Val (13)
              and then Data (Index_Value + 3) = Character'Val (10)
            then
               return Index_Value;
            end if;
         end loop;

         return 0;
      end Find_Header_End;

      procedure Append_Buffer is
         Count : constant Natural := Natural (Last - Buffer'First + 1);
      begin
         if Data_Length + Count > Max_Size then
            raise Web.Errors.Bad_Request_Error with "request too large";
         end if;

         for Offset in 0 .. Count - 1 loop
            Data (Data_Length + Offset + 1) :=
              Character'Val (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Offset)));
         end loop;
         Data_Length := Data_Length + Count;
      end Append_Buffer;
   begin
      loop
         Web.Connection.Receive (Conn, Buffer, Last);
         if Last < Buffer'First then
            raise Web.Errors.Bad_Request_Error with "client closed before request";
         end if;

         Append_Buffer;

         if not Header_Parsed then
            Header_End := Find_Header_End;
            if Header_End > 0 then
               declare
                  Raw : constant String := Data (1 .. Data_Length);
               begin
                  Reject_Unsupported_HTTP (Raw);
                  Content_Length := Header_Content_Length (Raw);
                  Expected_Size := Header_End + 3 + Content_Length;
                  Header_Parsed := True;
               end;
            end if;
         end if;

         if Header_Parsed then
            if Data_Length >= Expected_Size then
               declare
                  Raw : constant String := Data (1 .. Data_Length);
               begin
                  if Raw'Length > Expected_Size then
                     declare
                        Remainder : constant String := Raw (Expected_Size + 1 .. Raw'Last);
                     begin
                        if Index (Remainder, CRLF & CRLF) > 0 then
                           raise Web.Errors.Bad_Request_Error with "http pipelining is not supported";
                        end if;
                     end;
                  end if;
                  declare
                     Result : constant String := Raw (Raw'First .. Expected_Size);
                  begin
                     Free (Data);
                     return Result;
                  end;
               end;
            end if;
         end if;
      end loop;
   exception
      when others =>
         Free (Data);
         raise;
   end Read_Request;

   function WebSocket_Handshake (Request : Web.Request.Request_Type) return String is
      Accept_Value : constant String :=
        Web.WebSocket.Accept_Key
          (Web.Request.Header (Request, Web.Request.Sec_WebSocket_Key_Header));
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
         Peer : constant String :=
           GNAT.Sockets.Image (GNAT.Sockets.Get_Peer_Name (Socket));
         Request_Id : Natural := 0;
         Request_Time : constant String := Request_Timestamp (Ada.Calendar.Clock);
         Request_Status : Natural := 0;
         Request_Method : Unbounded_String := To_Unbounded_String ("-");
         Request_Path : Unbounded_String := To_Unbounded_String ("-");
         Client_Ip : Unbounded_String := To_Unbounded_String (Peer);
         Raw : Unbounded_String := Null_Unbounded_String;
         Request : Web.Request.Request_Type := Web.Request.Create ("GET", "/");
         Path   : Unbounded_String := Null_Unbounded_String;

         procedure Finalize_Request is
         begin
            --  `Get_Peer_Name` reports the client socket endpoint for this request.
            if Request_Status = 0 then
               Request_Status := 200;
            end if;

            Log_Request
              (Request_Id => Request_Id,
               Client_Ip => To_String (Client_Ip),
               Method => To_String (Request_Method),
               Path => To_String (Request_Path),
               Status => Request_Status,
               At_Time => Request_Time);

            if Close_When_Done then
               Web.Connection.Close (Conn);
            end if;
         end Finalize_Request;
      begin
         Request_Ids.Next (Request_Id);
         Raw := To_Unbounded_String (Read_Request (Conn));
         Request := Parse_Request (To_String (Raw));
         Request_Method := To_Unbounded_String (Web.Request.Method (Request));
         Request_Path := To_Unbounded_String (Web.Request.Path (Request));
         if Server_Config.Use_X_Forwarded_For
           and then Web.Request.Has_Header (Request, "x-forwarded-for")
         then
            declare
               Raw_Header : constant String :=
                 Web.Request.Header (Request, "x-forwarded-for");
               Separator : constant Natural := Index (Raw_Header, ",");
               Candidate : constant String :=
                 Trim
                   ((if Separator = 0
                     then Raw_Header
                     else Raw_Header (Raw_Header'First .. Separator - 1)),
                    Ada.Strings.Both);
            begin
               if Candidate'Length > 0 then
                  Client_Ip := To_Unbounded_String (Candidate);
               end if;
            end;
         end if;
         Path := Request_Path;

         Require_Allowed_Request (Request);

         if Web.WebSocket.Is_Upgrade (Request) then
            declare
               Cursor : constant Socket_Maps.Cursor := Sockets.Find (To_String (Path));
            begin
               if Socket_Maps.Has_Element (Cursor) then
                  Request_Status := 101;
                  Web.Connection.Send_All (Conn, WebSocket_Handshake (Request));
                  Socket_Maps.Element (Cursor) (Conn, Request);
               else
                  declare
                     Response : constant Web.Response.Response_Type :=
                       Build_Error_Response (Request, 404, "websocket endpoint not found");
                  begin
                     Request_Status := Web.Response.Status (Response);
                     Send_Response (Conn, Request, Response);
                  end;
               end if;
            end;
         else
            declare
               Response : constant Web.Response.Response_Type := Dispatch (Request);
            begin
               Request_Status := Web.Response.Status (Response);
               Send_Response (Conn, Request, Response);
            end;
         end if;

         Finalize_Request;
      exception
         when Error : Web.Errors.Bad_Request_Error | Web.Errors.Protocol_Error | Web.Errors.Security_Error =>
            declare
               Response : constant Web.Response.Response_Type :=
                 Build_Error_Response (Request, Error);
            begin
               Request_Status := Web.Response.Status (Response);
               Web.Logging.Warn
                 (Ada.Exceptions.Exception_Message (Error));
               Send_Response (Conn, Request, Response);
            end;
            Finalize_Request;
         when Error : others =>
            declare
               Response : constant Web.Response.Response_Type :=
                 Build_Error_Response (Request, Error);
            begin
               Request_Status := Web.Response.Status (Response);
               Web.Logging.Error (Ada.Exceptions.Exception_Information (Error));
               Send_Response (Conn, Request, Response);
            end;
            Finalize_Request;
      end;
   exception
      when others =>
         if Close_When_Done then
            GNAT.Sockets.Close_Socket (Socket);
         end if;
   end Handle_Connection;

   task type Connection_Worker (Queue : access Connection_Queue := null);

   task body Connection_Worker is
      Client : GNAT.Sockets.Socket_Type;
      TLS_Client : Boolean;
      Has_Job : Boolean;
   begin
      loop
         Queue.Dequeue (Client, TLS_Client, Has_Job);
         exit when not Has_Job;

         begin
            Handle_Connection (Client, TLS_Client);
         exception
            when Error : others =>
               Web.Logging.Error (Ada.Exceptions.Exception_Information (Error));
         end;

         Connection_Limiter.Release;
      end loop;
   end Connection_Worker;

   procedure Run_Internal
     (Host    : String;
      Port    : Natural;
      Use_TLS : Boolean) is
      Listener : GNAT.Sockets.Socket_Type;
      Address  : GNAT.Sockets.Sock_Addr_Type;
   begin
      Require_Bind_Port (Port);
      Require_Bind_Host (Host);
      GNAT.Sockets.Initialize;
      GNAT.Sockets.Create_Socket (Listener);
      --  Allow port reuse to avoid "Address already in use" errors on quick restarts
      GNAT.Sockets.Set_Socket_Option (Listener, GNAT.Sockets.Socket_Level, (GNAT.Sockets.Reuse_Address, True));
      Address.Addr := GNAT.Sockets.Inet_Addr (Host);
      Address.Port := GNAT.Sockets.Port_Type (Port);
      GNAT.Sockets.Bind_Socket (Listener, Address);
      GNAT.Sockets.Listen_Socket (Listener, Server_Config.Max_Connections);
      Server_State.Started (Listener, Address);
      Web.Logging.Info
        ("listening on "
         & (if Use_TLS then "https://" else "http://")
         & Host
         & ":"
         & Trimmed_Image (Port));

      declare
         Worker_Count : constant Positive := Positive (Server_Config.Max_Connections);
         Queue        : aliased Connection_Queue (Worker_Count);
         Workers      : array (1 .. Worker_Count) of Connection_Worker (Queue'Access);
         pragma Unreferenced (Workers);
      begin
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
                     Accepted : Boolean;
                  begin
                     Connection_Limiter.Try_Acquire (Accepted);
                     if Accepted then
                        begin
                           Queue.Enqueue (Socket, Use_TLS);
                        exception
                           when others =>
                              Connection_Limiter.Release;
                              GNAT.Sockets.Close_Socket (Socket);
                              raise;
                        end;
                     else
                        Web.Logging.Warn ("connection limit reached; closing accepted socket");
                        GNAT.Sockets.Close_Socket (Socket);
                     end if;
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
         Queue.Close;
      exception
         when others =>
            Queue.Close;
            raise;
      end;
      Server_State.Finished;
   exception
      when others =>
         Server_State.Finished;
         raise;
   end Run_Internal;

   procedure Run (Host : String; Port : Natural) is
   begin
      Require_Bind_Port (Port);
      Require_Bind_Host (Host);
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
      Require_Bind_Port (Port);
      Require_Bind_Host (Host);
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
