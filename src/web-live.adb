with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Exceptions;
with Ada.Calendar;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
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

   type Session_Record is record
      Id            : Unbounded_String;
      State         : App_State := Initial_State;
      Active_Socket : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Last_Seen     : Ada.Calendar.Time := Ada.Calendar.Clock;
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
      function Secure_Cookies return Boolean;
      function Max_WebSocket_Message return Natural;
      function Session_Count return Natural;
      function Active_WebSocket_Count return Natural;
      procedure Cleanup
        (Removed : out Natural;
         Sockets : in out Socket_Vectors.Vector);
   private
      Sessions : Session_Maps.Map;
      Timeout_Seconds : Natural := Web.Config.Default_Config.Session_Timeout;
      Secure_Cookie_Flag : Boolean := Web.Config.Default_Config.Secure_Cookies;
      Max_WebSocket_Message_Size : Natural := Web.Config.Default_Config.Max_WebSocket_Message;
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
               Last_Seen     => Ada.Calendar.Clock),
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

   function Secure_Cookies return Boolean is
   begin
      return Stores (Stores'First).Secure_Cookies;
   end Secure_Cookies;

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

      begin
         while not Done loop
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
                     declare
                        Patches : Web.Patch.Patch_List;
                        Event : constant Web.Events.Event :=
                          Web.Protocol.Decode_Client_Message (Payload);
                     begin
                        if Web.Events.Kind (Event) /= Web.Events.Hello_Event then
                           Stores (Store_Index).Dispatch_Event (Id, Event, Patches);
                           if not Patches.Items.Is_Empty then
                              Web.WebSocket.Send_Text (Conn, Web.Protocol.Encode_Patches (Patches));
                           end if;
                        end if;
                     end;

                  when Web.WebSocket.Ping_Frame =>
                     Web.WebSocket.Send_Pong (Conn, Payload);

                  when Web.WebSocket.Pong_Frame =>
                     null;

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
