with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Exceptions;
with Ada.Calendar;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Ada.Containers.Hashed_Sets;
with Web.Config;
with Web.Connection;
with Web.Cookie;
with Web.Errors;
with Web.Logging;
with Web.Protocol;
with Web.Security;
with Web.WebSocket;

package body Web.Live is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type GNAT.Sockets.Socket_Type;
   use type Web.Events.Event_Kind;

   Shard_Count : constant Positive := 8;

   --  Connection state for a session
   type Connection_State is (Disconnected, Connected, Reconnecting);

   --  Message ID set for deduplication
   function Message_Id_Hash (Item : Ada.Strings.Unbounded.Unbounded_String) return Ada.Containers.Hash_Type is
   begin
      return Ada.Strings.Hash (To_String (Item));
   end Message_Id_Hash;

   package Message_Id_Sets is new Ada.Containers.Hashed_Sets
     (Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      Hash => Message_Id_Hash,
      Equivalent_Elements => Ada.Strings.Unbounded."=");

   type Session_Record is record
      Id            : Unbounded_String;
      State         : App_State := Initial_State;
      Active_Socket : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Last_Seen     : Ada.Calendar.Time := Ada.Calendar.Clock;
      --  Connection hardening fields
      Conn_State    : Connection_State := Disconnected;
      Last_Ping_Time : Ada.Calendar.Time := Ada.Calendar.Clock;
      Last_Pong_Time : Ada.Calendar.Time := Ada.Calendar.Clock;
      Message_Count  : Natural := 0;
      Error_Count    : Natural := 0;
      Last_Error_Time: Ada.Calendar.Time := Ada.Calendar.Clock;
      --  Rate limiting
      Rate_Limit_Count : Natural := 0;
      Rate_Limit_Start : Ada.Calendar.Time := Ada.Calendar.Clock;
      --  Message deduplication
      Processed_Message_Id_Set : Message_Id_Sets.Set;
      Last_Message_Id  : Natural := 0;
      --  Reconnection support
      Is_Reconnecting : Boolean := False;
      Reconnect_Attempts : Natural := 0;
      Last_Reconnect_Time : Ada.Calendar.Time := Ada.Calendar.Clock;
   end record;

   package Session_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => Session_Record,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Socket_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => GNAT.Sockets.Socket_Type);

   procedure Close_Quietly (Socket : GNAT.Sockets.Socket_Type) is
   begin
      if Socket /= GNAT.Sockets.No_Socket then
         begin
            GNAT.Sockets.Shutdown_Socket (Socket);
         exception
            when others =>
               null;
         end;

         begin
            GNAT.Sockets.Close_Socket (Socket);
         exception
            when others =>
               null;
         end;
      end if;
   end Close_Quietly;

   protected type Store_Type is
      procedure Ensure (Id : String);
      procedure Create
        (Id      : String;
         Created : out Boolean);
      function Exists (Id : String) return Boolean;
      procedure Touch (Id : String);
      procedure Touch_If_Exists
        (Id    : String;
         Found : out Boolean);
      procedure Process (Id : String; Handler : State_Process);
      procedure Dispatch_Event
        (Id      : String;
         Event   : Web.Events.Event;
         Patches : out Web.Patch.Patch_List);
      procedure Attach_Socket
        (Id         : String;
         Socket     : GNAT.Sockets.Socket_Type;
         Old_Socket : out GNAT.Sockets.Socket_Type);
      procedure Detach_Socket
        (Id     : String;
         Socket : GNAT.Sockets.Socket_Type);
      procedure Set_Timeout (Seconds : Natural);
      procedure Set_Secure_Cookies (Enabled : Boolean);
      procedure Set_Max_WebSocket_Message (Bytes : Natural);
      procedure Set_Ping_Interval (Seconds : Natural);
      procedure Set_Rate_Limit (Count : Natural);
      procedure Set_Deduplication_Window (Seconds : Natural);
      function Secure_Cookies return Boolean;
      function Max_WebSocket_Message return Natural;
      function Ping_Interval return Natural;
      function Rate_Limit return Natural;
      function Deduplication_Window return Natural;
      function Session_Count return Natural;
      function Active_WebSocket_Count return Natural;
      function Is_Connected (Id : String) return Boolean;
      function Connection_Stats (Id : String) return String;
      
      --  Connection hardening helper procedures
      procedure Update_Ping_Time (Id : String);
      procedure Update_Pong_Time (Id : String);
      procedure Update_Message_Stats (Id : String);
      procedure Update_Error_Stats (Id : String);
      procedure Start_Reconnection (Id : String);
      procedure End_Reconnection (Id : String);
      procedure Check_And_Update_Rate_Limit (Id : String; Rate_Limit : Natural);
      procedure Check_And_Add_Message_Id (Id : String; Message_Id : String; Is_Duplicate : out Boolean);
      procedure Set_Connection_State (Id : String; State : Connection_State);
      procedure Cleanup
        (Removed : out Natural;
         Sockets : in out Socket_Vectors.Vector);
   private
      Sessions : Session_Maps.Map;
      Timeout_Seconds : Natural := Web.Config.Default_Config.Session_Timeout;
      Secure_Cookie_Flag : Boolean := Web.Config.Default_Config.Secure_Cookies;
      Max_WebSocket_Message_Size : Natural := Web.Config.Default_Config.Max_WebSocket_Message;
      Ping_Interval_Seconds : Natural := 30;  --  Default 30 seconds
      Rate_Limit_Count : Natural := 0;        --  0 means no rate limiting
      Deduplication_Window_Seconds : Natural := 60;  --  Default 60 seconds
   end Store_Type;

   protected body Store_Type is
      procedure Ensure (Id : String) is
         Created : Boolean;
      begin
         Create (Id, Created);
      end Ensure;

      procedure Create
        (Id      : String;
         Created : out Boolean)
      is
         Position : Session_Maps.Cursor;
         Inserted : Boolean;
      begin
         Created := False;

         if not Web.Security.Is_Valid_Session_Id (Id) then
            Web.Logging.Warn ("invalid session id rejected");
            return;
         end if;

         Session_Maps.Insert
           (Container => Sessions,
            Key       => Id,
            New_Item  =>
              (Id            => To_Unbounded_String (Id),
               State         => Initial_State,
               Active_Socket => GNAT.Sockets.No_Socket,
               Last_Seen     => Ada.Calendar.Clock,
               Conn_State    => Disconnected,
               Last_Ping_Time => Ada.Calendar.Clock,
               Last_Pong_Time => Ada.Calendar.Clock,
               Message_Count  => 0,
               Error_Count    => 0,
               Last_Error_Time=> Ada.Calendar.Clock,
               Rate_Limit_Count => 0,
               Rate_Limit_Start => Ada.Calendar.Clock,
               Processed_Message_Id_Set => Message_Id_Sets.Empty_Set,
               Last_Message_Id  => 0,
               Is_Reconnecting => False,
               Reconnect_Attempts => 0,
               Last_Reconnect_Time => Ada.Calendar.Clock),
            Position  => Position,
            Inserted  => Inserted);
         Created := Inserted;
      end Create;

      function Exists (Id : String) return Boolean is
      begin
         return Sessions.Contains (Id);
      end Exists;

      procedure Touch (Id : String) is
         Copy : Session_Record;
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
      begin
         if not Session_Maps.Has_Element (Position) then
            return;
         end if;

         Copy := Session_Maps.Element (Position);
         Copy.Last_Seen := Ada.Calendar.Clock;
         Sessions.Replace_Element (Position, Copy);
      end Touch;

      procedure Touch_If_Exists
        (Id    : String;
         Found : out Boolean)
      is
         Copy : Session_Record;
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
      begin
         Found := Session_Maps.Has_Element (Position);
         if not Found then
            return;
         end if;

         Copy := Session_Maps.Element (Position);
         Copy.Last_Seen := Ada.Calendar.Clock;
         Sessions.Replace_Element (Position, Copy);
      end Touch_If_Exists;

      procedure Process (Id : String; Handler : State_Process) is
         Copy : Session_Record;
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
      begin
         if not Session_Maps.Has_Element (Position) then
            return;
         end if;

         Copy := Session_Maps.Element (Position);
         Copy.Last_Seen := Ada.Calendar.Clock;
         Handler (Copy.State);
         Sessions.Replace_Element (Position, Copy);
      end Process;

      procedure Dispatch_Event
        (Id      : String;
         Event   : Web.Events.Event;
         Patches : out Web.Patch.Patch_List)
      is
         Copy : Session_Record;
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
      begin
         Patches := (Items => Web.Patch.Patch_Vectors.Empty_Vector);
         if not Session_Maps.Has_Element (Position) then
            return;
         end if;

         Copy := Session_Maps.Element (Position);
         Copy.Last_Seen := Ada.Calendar.Clock;
         Patches := Dispatch (Copy.State, Event);
         Sessions.Replace_Element (Position, Copy);
      exception
         when Error : others =>
            Web.Logging.Error ("live dispatch failed: " & Ada.Exceptions.Exception_Message (Error));
            Patches := (Items => Web.Patch.Patch_Vectors.Empty_Vector);
      end Dispatch_Event;

      procedure Attach_Socket
        (Id         : String;
         Socket     : GNAT.Sockets.Socket_Type;
         Old_Socket : out GNAT.Sockets.Socket_Type)
      is
         Copy : Session_Record;
         Position : Session_Maps.Cursor;
      begin
         Position := Sessions.Find (Id);
         if not Session_Maps.Has_Element (Position) then
            Ensure (Id);
            Position := Sessions.Find (Id);
         end if;

         if not Session_Maps.Has_Element (Position) then
            Old_Socket := GNAT.Sockets.No_Socket;
            return;
         end if;

         Copy := Session_Maps.Element (Position);
         Old_Socket := Copy.Active_Socket;
         Copy.Active_Socket := Socket;
         Copy.Last_Seen := Ada.Calendar.Clock;
         Copy.Conn_State := Connected;
         Copy.Is_Reconnecting := False;
         Copy.Reconnect_Attempts := 0;
         Sessions.Replace_Element (Position, Copy);
      end Attach_Socket;

      procedure Detach_Socket
        (Id     : String;
         Socket : GNAT.Sockets.Socket_Type)
      is
         Copy : Session_Record;
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
      begin
         if not Session_Maps.Has_Element (Position) then
            return;
         end if;

         Copy := Session_Maps.Element (Position);
         if Copy.Active_Socket = Socket then
            Copy.Active_Socket := GNAT.Sockets.No_Socket;
            Copy.Conn_State := Disconnected;
            Copy.Last_Ping_Time := Ada.Calendar.Clock;
            Copy.Last_Pong_Time := Ada.Calendar.Clock;
            Sessions.Replace_Element (Position, Copy);
         end if;
      end Detach_Socket;

      procedure Set_Timeout (Seconds : Natural) is
      begin
         Timeout_Seconds := Seconds;
      end Set_Timeout;

      procedure Set_Secure_Cookies (Enabled : Boolean) is
      begin
         Secure_Cookie_Flag := Enabled;
      end Set_Secure_Cookies;

      procedure Set_Max_WebSocket_Message (Bytes : Natural) is
      begin
         Max_WebSocket_Message_Size := Bytes;
      end Set_Max_WebSocket_Message;

      function Secure_Cookies return Boolean is
      begin
         return Secure_Cookie_Flag;
      end Secure_Cookies;

      function Max_WebSocket_Message return Natural is
      begin
         return Max_WebSocket_Message_Size;
      end Max_WebSocket_Message;

      procedure Set_Ping_Interval (Seconds : Natural) is
      begin
         Ping_Interval_Seconds := Seconds;
      end Set_Ping_Interval;

      procedure Set_Rate_Limit (Count : Natural) is
      begin
         Rate_Limit_Count := Count;
      end Set_Rate_Limit;

      procedure Set_Deduplication_Window (Seconds : Natural) is
      begin
         Deduplication_Window_Seconds := Seconds;
      end Set_Deduplication_Window;

      function Ping_Interval return Natural is
      begin
         return Ping_Interval_Seconds;
      end Ping_Interval;

      function Rate_Limit return Natural is
      begin
         return Rate_Limit_Count;
      end Rate_Limit;

      function Deduplication_Window return Natural is
      begin
         return Deduplication_Window_Seconds;
      end Deduplication_Window;

      function Session_Count return Natural is
      begin
         return Natural (Sessions.Length);
      end Session_Count;

      function Active_WebSocket_Count return Natural is
         Count : Natural := 0;
      begin
         for Item of Sessions loop
            if Item.Active_Socket /= GNAT.Sockets.No_Socket then
               Count := Count + 1;
            end if;
         end loop;

         return Count;
      end Active_WebSocket_Count;

      function Is_Connected (Id : String) return Boolean is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
      begin
         if not Session_Maps.Has_Element (Position) then
            return False;
         end if;
         Copy := Session_Maps.Element (Position);
         return Copy.Active_Socket /= GNAT.Sockets.No_Socket;
      end Is_Connected;

      function Connection_Stats (Id : String) return String is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
      begin
         if not Session_Maps.Has_Element (Position) then
            return "";
         end if;
         Copy := Session_Maps.Element (Position);
         return "msgs:" & Natural'Image (Copy.Message_Count) & 
                ", errors:" & Natural'Image (Copy.Error_Count) &
                ", state:" & Connection_State'Image (Copy.Conn_State) &
                ", reconnects:" & Natural'Image (Copy.Reconnect_Attempts);
      end Connection_Stats;

      --  Connection hardening helper implementations
      procedure Update_Ping_Time (Id : String) is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
      begin
         if Session_Maps.Has_Element (Position) then
            Copy := Session_Maps.Element (Position);
            Copy.Last_Ping_Time := Ada.Calendar.Clock;
            Sessions.Replace_Element (Position, Copy);
         end if;
      end Update_Ping_Time;

      procedure Update_Pong_Time (Id : String) is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
      begin
         if Session_Maps.Has_Element (Position) then
            Copy := Session_Maps.Element (Position);
            Copy.Last_Pong_Time := Ada.Calendar.Clock;
            Sessions.Replace_Element (Position, Copy);
         end if;
      end Update_Pong_Time;

      procedure Update_Message_Stats (Id : String) is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
      begin
         if Session_Maps.Has_Element (Position) then
            Copy := Session_Maps.Element (Position);
            Copy.Message_Count := Copy.Message_Count + 1;
            Copy.Last_Seen := Ada.Calendar.Clock;
            Copy.Conn_State := Connected;
            Sessions.Replace_Element (Position, Copy);
         end if;
      end Update_Message_Stats;

      procedure Update_Error_Stats (Id : String) is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
      begin
         if Session_Maps.Has_Element (Position) then
            Copy := Session_Maps.Element (Position);
            Copy.Error_Count := Copy.Error_Count + 1;
            Copy.Last_Error_Time := Ada.Calendar.Clock;
            Sessions.Replace_Element (Position, Copy);
         end if;
      end Update_Error_Stats;

      procedure Start_Reconnection (Id : String) is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
      begin
         if Session_Maps.Has_Element (Position) then
            Copy := Session_Maps.Element (Position);
            Copy.Is_Reconnecting := True;
            Copy.Reconnect_Attempts := Copy.Reconnect_Attempts + 1;
            Copy.Last_Reconnect_Time := Ada.Calendar.Clock;
            Sessions.Replace_Element (Position, Copy);
         end if;
      end Start_Reconnection;

      procedure End_Reconnection (Id : String) is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
      begin
         if Session_Maps.Has_Element (Position) then
            Copy := Session_Maps.Element (Position);
            Copy.Is_Reconnecting := False;
            Sessions.Replace_Element (Position, Copy);
         end if;
      end End_Reconnection;

      procedure Check_And_Update_Rate_Limit (Id : String; Rate_Limit : Natural) is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
         Current_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      begin
         if Session_Maps.Has_Element (Position) and then Rate_Limit > 0 then
            Copy := Session_Maps.Element (Position);
            
            --  Check if rate limit window has expired (1 minute)
            if Current_Time - Copy.Rate_Limit_Start >= Duration (60) then
               Copy.Rate_Limit_Count := 0;
               Copy.Rate_Limit_Start := Current_Time;
            end if;
            
            --  Increment and check rate limit
            Copy.Rate_Limit_Count := Copy.Rate_Limit_Count + 1;
            if Copy.Rate_Limit_Count > Rate_Limit then
               Web.Logging.Warn ("rate limit exceeded for session " & Id & 
                               " (" & Natural'Image (Copy.Rate_Limit_Count) & 
                               " messages in last minute)");
               raise Web.Errors.Protocol_Error with "rate limit exceeded";
            end if;
            
            Sessions.Replace_Element (Position, Copy);
         end if;
      end Check_And_Update_Rate_Limit;

      procedure Check_And_Add_Message_Id 
        (Id : String; Message_Id : String; Is_Duplicate : out Boolean) is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
         Deduplication_Window : constant Natural := Deduplication_Window_Seconds;
         Message_Id_U : constant Unbounded_String := To_Unbounded_String (Message_Id);
      begin
         Is_Duplicate := False;
         if Session_Maps.Has_Element (Position) and then Deduplication_Window > 0 
           and then Message_Id'Length > 0 then
            Copy := Session_Maps.Element (Position);
            
            --  Check if this message ID has been processed
            if Copy.Processed_Message_Id_Set.Contains (Message_Id_U) then
               Web.Logging.Debug ("duplicate message detected: " & Message_Id);
               Is_Duplicate := True; -- Duplicate detected
               return;
            end if;
            
            --  Add message ID to processed set
            Copy.Processed_Message_Id_Set.Include (Message_Id_U);
            Sessions.Replace_Element (Position, Copy);
         end if;
      end Check_And_Add_Message_Id;

      procedure Set_Connection_State (Id : String; State : Connection_State) is
         Position : constant Session_Maps.Cursor := Sessions.Find (Id);
         Copy : Session_Record;
      begin
         if Session_Maps.Has_Element (Position) then
            Copy := Session_Maps.Element (Position);
            Copy.Conn_State := State;
            Sessions.Replace_Element (Position, Copy);
         end if;
      end Set_Connection_State;

      procedure Cleanup
        (Removed : out Natural;
         Sockets : in out Socket_Vectors.Vector)
      is
         Now_Value : constant Ada.Calendar.Time := Ada.Calendar.Clock;
         Cursor : Session_Maps.Cursor;

         function Expired (Session : Session_Record) return Boolean is
         begin
            return Timeout_Seconds = 0
              or else Now_Value - Session.Last_Seen >= Duration (Timeout_Seconds);
         end Expired;
      begin
         Removed := 0;

         if Sessions.Is_Empty then
            return;
         end if;

         Cursor := Sessions.First;
         while Session_Maps.Has_Element (Cursor) loop
            declare
               Next : constant Session_Maps.Cursor := Session_Maps.Next (Cursor);
               Key  : constant String := Session_Maps.Key (Cursor);
               Item : constant Session_Record := Session_Maps.Element (Cursor);
            begin
               if Expired (Item) then
                  if Item.Active_Socket /= GNAT.Sockets.No_Socket then
                     Sockets.Append (Item.Active_Socket);
                  end if;

                  Sessions.Delete (Key);
                  Removed := Removed + 1;
               end if;
               Cursor := Next;
            end;
         end loop;
      end Cleanup;
   end Store_Type;

   type Store_Array is array (Positive range <>) of Store_Type;

   Stores : Store_Array (1 .. Shard_Count);

   function Shard_Index (Id : String) return Positive is
      Value : Natural := 0;
   begin
      for Ch of Id loop
         Value := (Value + Character'Pos (Ch)) mod Shard_Count;
      end loop;

      return Value + 1;
   end Shard_Index;

   task type Cleanup_Task_Type is
      entry Start (Interval_Seconds : Positive);
      entry Stop;
   end Cleanup_Task_Type;

   type Cleanup_Task_Access is access Cleanup_Task_Type;

   Cleanup_Worker : Cleanup_Task_Access := null;

   task body Cleanup_Task_Type is
      Period : Positive := 60;
   begin
      accept Start (Interval_Seconds : Positive) do
         Period := Interval_Seconds;
      end Start;

      loop
         select
            accept Stop;
            exit;
         or
            delay Duration (Period);
            declare
               Removed : constant Natural := Cleanup_Sessions;
            begin
               if Removed > 0 then
                  Web.Logging.Debug ("expired sessions cleaned: " & Natural'Image (Removed));
               end if;
            end;
         end select;
      end loop;
   end Cleanup_Task_Type;

   function Cookie_Id (Request : Web.Request.Request_Type) return String is
      Cookie_Header : constant String := Web.Request.Header (Request, "Cookie");
   begin
      if Cookie_Header'Length > 0 then
         declare
            Jar : constant Web.Cookie.Cookie_Jar := Web.Cookie.Parse (Cookie_Header);
            Session_Count : constant Natural := Web.Cookie.Count (Jar, "wf_session");
         begin
            if Session_Count = 1 then
               declare
                  Id : constant String := Web.Cookie.Value (Jar, "wf_session");
               begin
                  if Web.Security.Is_Valid_Session_Id (Id) then
                     return Id;
                  end if;
               end;
            end if;

            if Session_Count > 1 then
               Web.Logging.Warn ("duplicate session cookie rejected");
            end if;
         end;
      end if;

      return "";
   end Cookie_Id;

   function Find_Or_Create_Session (Request : Web.Request.Request_Type) return String is
      Id : constant String := Cookie_Id (Request);
   begin
      if Id'Length > 0 then
         declare
            Index_Value : constant Positive := Shard_Index (Id);
            Found       : Boolean;
         begin
            Stores (Index_Value).Touch_If_Exists (Id, Found);
            if Found then
               return Id;
            end if;
         end;
      end if;

      for Attempt in 1 .. 16 loop
         declare
            New_Id  : constant String := Web.Security.New_Session_Id;
            Created : Boolean;
         begin
            Stores (Shard_Index (New_Id)).Create (New_Id, Created);
            if Created then
               return New_Id;
            end if;
         end;
      end loop;

      raise Web.Errors.Security_Error with "unable to allocate unique session id";
   end Find_Or_Create_Session;

   function Require_Session (Request : Web.Request.Request_Type) return String is
      Id : constant String := Cookie_Id (Request);
   begin
      if Id'Length > 0 then
         declare
            Index_Value : constant Positive := Shard_Index (Id);
            Found       : Boolean;
         begin
            Stores (Index_Value).Touch_If_Exists (Id, Found);
            if Found then
               return Id;
            end if;
         end;
      end if;
      return "";
   end Require_Session;

   function Session_Cookie_Header (Id : String) return String is
   begin
      if not Web.Security.Is_Valid_Session_Id (Id) then
         raise Web.Errors.Security_Error with "invalid session id";
      end if;

      return Web.Cookie.Set_Cookie
        ("wf_session",
         Id,
         Web.Cookie.Cookie_Options'
           (Path      => "/",
            Http_Only => True,
            Secure    => Stores (Stores'First).Secure_Cookies,
            Same_Site => Web.Cookie.Lax,
            Max_Age   => -1));
   end Session_Cookie_Header;

   function Html_Response (Session : String; Content : String) return Web.Response.Response_Type is
      Response : Web.Response.Response_Type := Web.Response.Html (Content);
   begin
      Web.Response.Set_Header (Response, "Set-Cookie", Session_Cookie_Header (Session));
      return Response;
   end Html_Response;

   function Html_Response
     (Request : Web.Request.Request_Type;
      Content : String) return Web.Response.Response_Type
   is
   begin
      return Html_Response (Find_Or_Create_Session (Request), Content);
   end Html_Response;

   procedure Configure (Config : Web.Config.Config_Type) is
   begin
      if Config.Max_WebSocket_Message = 0 then
         raise Web.Errors.Security_Error with "max websocket message must be positive";
      end if;

      for Index_Value in Stores'Range loop
         Stores (Index_Value).Set_Secure_Cookies (Config.Secure_Cookies);
         Stores (Index_Value).Set_Timeout (Config.Session_Timeout);
         Stores (Index_Value).Set_Max_WebSocket_Message (Config.Max_WebSocket_Message);
      end loop;
   end Configure;

   procedure Set_Secure_Cookies (Enabled : Boolean) is
   begin
      for Index_Value in Stores'Range loop
         Stores (Index_Value).Set_Secure_Cookies (Enabled);
      end loop;
   end Set_Secure_Cookies;

   procedure Set_Ping_Interval (Seconds : Natural) is
   begin
      for Index_Value in Stores'Range loop
         Stores (Index_Value).Set_Ping_Interval (Seconds);
      end loop;
   end Set_Ping_Interval;

   procedure Set_Rate_Limit (Count : Natural) is
   begin
      for Index_Value in Stores'Range loop
         Stores (Index_Value).Set_Rate_Limit (Count);
      end loop;
   end Set_Rate_Limit;

   procedure Set_Deduplication_Window (Seconds : Natural) is
   begin
      for Index_Value in Stores'Range loop
         Stores (Index_Value).Set_Deduplication_Window (Seconds);
      end loop;
   end Set_Deduplication_Window;

   function Secure_Cookies return Boolean is
   begin
      return Stores (Stores'First).Secure_Cookies;
   end Secure_Cookies;

   function Ping_Interval return Natural is
   begin
      return Stores (Stores'First).Ping_Interval;
   end Ping_Interval;

   function Rate_Limit return Natural is
   begin
      return Stores (Stores'First).Rate_Limit;
   end Rate_Limit;

   function Deduplication_Window return Natural is
   begin
      return Stores (Stores'First).Deduplication_Window;
   end Deduplication_Window;

   function Session_Count return Natural is
   begin
      declare
         Count : Natural := 0;
      begin
         for Index_Value in Stores'Range loop
            Count := Count + Stores (Index_Value).Session_Count;
         end loop;

         return Count;
      end;
   end Session_Count;

   function Active_WebSocket_Count return Natural is
   begin
      declare
         Count : Natural := 0;
      begin
         for Index_Value in Stores'Range loop
            Count := Count + Stores (Index_Value).Active_WebSocket_Count;
         end loop;

         return Count;
      end;
   end Active_WebSocket_Count;

   function Is_Connected (Id : String) return Boolean is
      Index_Value : Positive := Shard_Index (Id);
   begin
      return Stores (Index_Value).Is_Connected (Id);
   end Is_Connected;

   function Connection_Stats (Id : String) return String is
      Index_Value : Positive := Shard_Index (Id);
   begin
      return Stores (Index_Value).Connection_Stats (Id);
   end Connection_Stats;

   procedure With_State (Id : String; Process : State_Process) is
      Index_Value : Positive;
   begin
      if not Web.Security.Is_Valid_Session_Id (Id) then
         raise Web.Errors.Security_Error with "invalid session id";
      end if;

      if Process = null then
         raise Web.Errors.Security_Error with "state process must not be null";
      end if;

      Index_Value := Shard_Index (Id);
      Stores (Index_Value).Ensure (Id);
      Stores (Index_Value).Process (Id, Process);
   end With_State;

   procedure Set_Session_Timeout (Seconds : Natural) is
   begin
      for Index_Value in Stores'Range loop
         Stores (Index_Value).Set_Timeout (Seconds);
      end loop;
   end Set_Session_Timeout;

   function Cleanup_Sessions return Natural is
      Removed : Natural;
      Sockets : Socket_Vectors.Vector;
   begin
      Removed := 0;
      Sockets.Clear;
      for Index_Value in Stores'Range loop
         declare
            Shard_Removed : Natural;
         begin
            Stores (Index_Value).Cleanup (Shard_Removed, Sockets);
            Removed := Removed + Shard_Removed;
         end;
      end loop;

      for Socket of Sockets loop
         Close_Quietly (Socket);
      end loop;

      return Removed;
   end Cleanup_Sessions;

   procedure Start_Cleanup_Task (Interval_Seconds : Positive := 60) is
   begin
      if Cleanup_Worker = null then
         Cleanup_Worker := new Cleanup_Task_Type;
         Cleanup_Worker.Start (Interval_Seconds);
      end if;
   end Start_Cleanup_Task;

   procedure Stop_Cleanup_Task is
   begin
      if Cleanup_Worker /= null then
         begin
            Cleanup_Worker.Stop;
         exception
            when Tasking_Error =>
               null;
         end;
         Cleanup_Worker := null;
      end if;
   end Stop_Cleanup_Task;

   function Cleanup_Task_Running return Boolean is
   begin
      return Cleanup_Worker /= null;
   end Cleanup_Task_Running;

   procedure Run_Connection
     (Conn : in out Web.Connection.Connection_Type;
      Id   : String)
   is
      Done : Boolean := False;
      Socket : constant GNAT.Sockets.Socket_Type := Web.Connection.Socket (Conn);
      Old_Socket : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Store_Index : Positive;
      Last_Ping_Time : Ada.Calendar.Time;
      Ping_Interval : Natural;
   begin
      if not Web.Security.Is_Valid_Session_Id (Id) then
         raise Web.Errors.Security_Error with "invalid session id";
      end if;

      Store_Index := Shard_Index (Id);
      Stores (Store_Index).Attach_Socket (Id, Socket, Old_Socket);
      if Old_Socket /= GNAT.Sockets.No_Socket and then Old_Socket /= Socket then
         Web.Logging.Info ("replacing websocket for session " & Id);
         Close_Quietly (Old_Socket);
      end if;

      --  Get configuration values for this session
      Ping_Interval := Stores (Store_Index).Ping_Interval;
      Last_Ping_Time := Ada.Calendar.Clock;

      begin
         while not Done loop
            --  Check if we need to send a ping for connection health
            if Ping_Interval > 0 and then Stores (Store_Index).Is_Connected (Id) then
               declare
                  Current_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;
               begin
                  if Current_Time - Last_Ping_Time >= Duration (Ping_Interval) then
                     begin
                        Web.WebSocket.Send_Text (Conn, Web.Protocol.Create_Ping_Message);
                        Last_Ping_Time := Current_Time;
                        Web.Logging.Debug ("sent ping to session " & Id);
                     exception
                        when Error : others =>
                           Web.Logging.Warn ("failed to send ping to session " & Id & ": " & 
                                           Ada.Exceptions.Exception_Message (Error));
                           Done := True;
                     end;
                  end if;
               end;
            end if;

            --  Cleanup old message IDs for deduplication
            declare
               Deduplication_Window : constant Natural := Stores (Store_Index).Deduplication_Window;
            begin
               if Deduplication_Window > 0 then
                  --  This would require access to the session record, which we'll handle in Process_Frame
                  null;
               end if;
            end;

            declare
               procedure Process_Frame
                 (Kind    : Web.WebSocket.Opcode;
                  Payload : String);

               procedure Process_Frame
                 (Kind    : Web.WebSocket.Opcode;
                  Payload : String)
               is
               begin
                  case Kind is
                  when Web.WebSocket.Text_Frame =>
                     --  Handle text messages with connection hardening
                     begin
                        --  Check for ping messages first
                        if Web.Protocol.Is_Ping_Message (Payload) then
                           Web.Logging.Debug ("received ping from session " & Id);
                           Web.WebSocket.Send_Text (Conn, Web.Protocol.Create_Pong_Message);
                           
                           --  Update session ping time
                           Stores (Store_Index).Update_Ping_Time (Id);
                           return;
                        end if;

                        --  Check for pong messages
                        if Web.Protocol.Is_Pong_Message (Payload) then
                           Web.Logging.Debug ("received pong from session " & Id);
                           
                           --  Update session pong time
                           Stores (Store_Index).Update_Pong_Time (Id);
                           return;
                        end if;

                        --  Check for acknowledgment messages
                        if Web.Protocol.Is_Ack_Message (Payload) then
                           declare
                              Ack_Id : constant String := Web.Protocol.Get_Ack_Id_From_Message (Payload);
                           begin
                              if Ack_Id'Length > 0 then
                                 Web.Logging.Debug ("received ack " & Ack_Id & " from session " & Id);
                                 --  Mark acknowledgment as received (could track this if needed)
                              end if;
                           end;
                           return;
                        end if;

                        --  Check for server reconnect requests
                        if Web.Protocol.Is_Server_Reconnect (Payload) then
                           Web.Logging.Info ("received server reconnect request from session " & Id);
                           
                           --  Update session state for reconnection
                           Stores (Store_Index).Start_Reconnection (Id);
                           return;
                        end if;

                        --  Handle regular events
                        declare
                           Patches : Web.Patch.Patch_List;
                           Event : constant Web.Events.Event := Web.Protocol.Decode_Client_Message (Payload);
                           Event_Message_Id : constant String := Web.Events.Get_Message_Id (Event);
                           Event_Ack_Id : constant String := Web.Events.Get_Ack_Id (Event);
                           Is_Reconnecting : constant Boolean := Web.Protocol.Has_Reconnecting (Payload);
                           Rate_Limit : constant Natural := Stores (Store_Index).Rate_Limit;
                           Is_Duplicate : Boolean := False;
                        begin
                           --  Check for duplicate message first
                           declare
                              Is_Duplicate : Boolean;
                           begin
                              Stores (Store_Index).Check_And_Add_Message_Id (Id, Event_Message_Id, Is_Duplicate);
                              if Is_Duplicate then
                                 Web.Logging.Debug ("duplicate message detected: " & Event_Message_Id);
                                 return;  --  Skip processing duplicate message
                              end if;
                           end;

                           --  Check rate limiting
                           Stores (Store_Index).Check_And_Update_Rate_Limit (Id, Rate_Limit);

                           --  Handle reconnection state
                           if Is_Reconnecting then
                              Stores (Store_Index).Start_Reconnection (Id);
                              Web.Logging.Info ("session " & Id & " is reconnecting");
                           else
                              Stores (Store_Index).End_Reconnection (Id);
                           end if;

                           --  Update message statistics
                           Stores (Store_Index).Update_Message_Stats (Id);

                           --  Process the event if it's not a hello event
                           if Web.Events.Kind (Event) /= Web.Events.Hello_Event then
                              Stores (Store_Index).Dispatch_Event (Id, Event, Patches);

                              --  Add message ID to patches if this event requires acknowledgment
                              if Web.Events.Has_Ack_Id (Event) and then not Patches.Items.Is_Empty then
                                 --  For now, we'll send patches with ack support
                                 --  In a more complete implementation, we'd track which patches need acks
                                 declare
                                    Response : constant String := Web.Protocol.Encode_Patches (Patches);
                                 begin
                                    Web.WebSocket.Send_Text (Conn, Response);
                                    
                                    --  If the original event had an ackId, we could send an ack response
                                    if Event_Ack_Id'Length > 0 then
                                       Web.WebSocket.Send_Text (Conn, Web.Protocol.Create_Ack_Message (Event_Ack_Id));
                                    end if;
                                 end;
                              elsif not Patches.Items.Is_Empty then
                                 Web.WebSocket.Send_Text (Conn, Web.Protocol.Encode_Patches (Patches));
                              end if;
                           end if;

                        exception
                           when Error : others =>
                              --  Update error statistics
                              Stores (Store_Index).Update_Error_Stats (Id);
                              raise;
                        end;
                     end;

                  when Web.WebSocket.Ping_Frame =>
                     --  Handle WebSocket-level ping
                     Web.WebSocket.Send_Pong (Conn, Payload);
                     Web.Logging.Debug ("received WebSocket ping from session " & Id);

                  when Web.WebSocket.Pong_Frame =>
                     --  Handle WebSocket-level pong
                     Web.Logging.Debug ("received WebSocket pong from session " & Id);

                  when Web.WebSocket.Close_Frame =>
                     Web.WebSocket.Send_Close (Conn);
                     Done := True;
               end case;
               end Process_Frame;

               procedure Receive is new Web.WebSocket.Receive_And_Process (Process_Frame);
            begin
               Receive (Conn, Stores (Store_Index).Max_WebSocket_Message);
            end;
         end loop;
      exception
         when Error : Web.Errors.Protocol_Error | Web.Errors.Bad_Request_Error =>
            Web.Logging.Warn ("closing websocket: " & Ada.Exceptions.Exception_Message (Error));
            Web.WebSocket.Send_Close (Conn);
         when Error : others =>
            Web.Logging.Error ("websocket loop failed: " & Ada.Exceptions.Exception_Information (Error));
            Web.WebSocket.Send_Close (Conn);
      end;

      Stores (Store_Index).Detach_Socket (Id, Socket);
   end Run_Connection;

   procedure Run_Connection (Socket : GNAT.Sockets.Socket_Type; Id : String) is
      Conn : Web.Connection.Connection_Type;
   begin
      Web.Connection.Open_Plain (Conn, Socket);
      Run_Connection (Conn, Id);
   end Run_Connection;

   procedure WebSocket_Handler
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type)
   is
      Id : constant String := Find_Or_Create_Session (Request);
   begin
      Run_Connection (Conn, Id);
   end WebSocket_Handler;
end Web.Live;
