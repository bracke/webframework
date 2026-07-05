with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;
with Ada.Exceptions;
with Ada.Calendar;
with Ada.Strings.Fixed;
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

   type Session_Record is record
      Id            : Unbounded_String;
      State         : App_State := Initial_State;
      Active_Socket : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Last_Seen     : Ada.Calendar.Time := Ada.Calendar.Clock;
   end record;

   package Session_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Natural,
      Element_Type => Session_Record);

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

   protected Store is
      procedure Ensure (Id : String);
      procedure Create
        (Id      : String;
         Created : out Boolean);
      function Exists (Id : String) return Boolean;
      procedure Touch (Id : String);
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
      procedure Cleanup
        (Removed : out Natural;
         Sockets : in out Socket_Vectors.Vector);
   private
      Sessions : Session_Vectors.Vector;
      Timeout_Seconds : Natural := Web.Config.Default_Config.Session_Timeout;
      Secure_Cookie_Flag : Boolean := Web.Config.Default_Config.Secure_Cookies;
      Max_WebSocket_Message_Size : Natural := Web.Config.Default_Config.Max_WebSocket_Message;
   end Store;

   protected body Store is
      function Index_Of (Id : String) return Natural is
      begin
         for Index_Value in Sessions.First_Index .. Sessions.Last_Index loop
            if To_String (Sessions (Index_Value).Id) = Id then
               return Index_Value;
            end if;
         end loop;
         return Natural'Last;
      end Index_Of;

      procedure Ensure (Id : String) is
         Created : Boolean;
      begin
         Create (Id, Created);
      end Ensure;

      procedure Create
        (Id      : String;
         Created : out Boolean)
      is
      begin
         Created := False;

         if not Web.Security.Is_Valid_Session_Id (Id) then
            Web.Logging.Warn ("invalid session id rejected");
            return;
         end if;

         if Index_Of (Id) = Natural'Last then
            declare
               Item : constant Session_Record :=
                  (Id            => To_Unbounded_String (Id),
                   State         => Initial_State,
                   Active_Socket => GNAT.Sockets.No_Socket,
                   Last_Seen     => Ada.Calendar.Clock);
            begin
               Sessions.Append (Item);
               Created := True;
            end;
         end if;
      end Create;

      function Exists (Id : String) return Boolean is
      begin
         return Index_Of (Id) /= Natural'Last;
      end Exists;

      procedure Touch (Id : String) is
         Index_Value : constant Natural := Index_Of (Id);
         Copy        : Session_Record;
      begin
         if Index_Value = Natural'Last then
            return;
         end if;

         Copy := Sessions (Index_Value);
         Copy.Last_Seen := Ada.Calendar.Clock;
         Sessions.Replace_Element (Index_Value, Copy);
      end Touch;

      procedure Process (Id : String; Handler : State_Process) is
         Index_Value : constant Natural := Index_Of (Id);
         Copy        : Session_Record;
      begin
         if Index_Value = Natural'Last then
            return;
         end if;

         Copy := Sessions (Index_Value);
         Copy.Last_Seen := Ada.Calendar.Clock;
         Handler (Copy.State);
         Sessions.Replace_Element (Index_Value, Copy);
      end Process;

      procedure Dispatch_Event
        (Id      : String;
         Event   : Web.Events.Event;
         Patches : out Web.Patch.Patch_List)
      is
         Index_Value : constant Natural := Index_Of (Id);
         Copy        : Session_Record;
      begin
         Patches := (Items => Web.Patch.Patch_Vectors.Empty_Vector);
         if Index_Value = Natural'Last then
            return;
         end if;

         Copy := Sessions (Index_Value);
         Copy.Last_Seen := Ada.Calendar.Clock;
         Patches := Dispatch (Copy.State, Event);
         Sessions.Replace_Element (Index_Value, Copy);
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
         Index_Value : Natural := Index_Of (Id);
         Copy        : Session_Record;
      begin
         if Index_Value = Natural'Last then
            Ensure (Id);
            Index_Value := Index_Of (Id);
         end if;

         if Index_Value = Natural'Last then
            Old_Socket := GNAT.Sockets.No_Socket;
            return;
         end if;

         Copy := Sessions (Index_Value);
         Old_Socket := Copy.Active_Socket;
         Copy.Active_Socket := Socket;
         Copy.Last_Seen := Ada.Calendar.Clock;
         Sessions.Replace_Element (Index_Value, Copy);
      end Attach_Socket;

      procedure Detach_Socket
        (Id     : String;
         Socket : GNAT.Sockets.Socket_Type)
      is
         Index_Value : constant Natural := Index_Of (Id);
         Copy        : Session_Record;
      begin
         if Index_Value = Natural'Last then
            return;
         end if;

         Copy := Sessions (Index_Value);
         if Copy.Active_Socket = Socket then
            Copy.Active_Socket := GNAT.Sockets.No_Socket;
            Sessions.Replace_Element (Index_Value, Copy);
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

      procedure Cleanup
        (Removed : out Natural;
         Sockets : in out Socket_Vectors.Vector)
      is
         Now_Value : constant Ada.Calendar.Time := Ada.Calendar.Clock;
         Index_Value : Natural;

         function Expired (Session : Session_Record) return Boolean is
         begin
            return Timeout_Seconds = 0
              or else Now_Value - Session.Last_Seen >= Duration (Timeout_Seconds);
         end Expired;
      begin
         Removed := 0;
         Sockets.Clear;

         if Sessions.Is_Empty then
            return;
         end if;

         Index_Value := Sessions.First_Index;
         while not Sessions.Is_Empty and then Index_Value <= Sessions.Last_Index loop
            declare
               Item : constant Session_Record := Sessions (Index_Value);
            begin
               if Expired (Item) then
                  if Item.Active_Socket /= GNAT.Sockets.No_Socket then
                     Sockets.Append (Item.Active_Socket);
                  end if;

                  Sessions.Delete (Index_Value);
                  Removed := Removed + 1;
               else
                  Index_Value := Index_Value + 1;
               end if;
            end;
         end loop;
      end Cleanup;
   end Store;

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
   begin
      if Web.Request.Has_Header (Request, "Cookie") then
         declare
            Jar : constant Web.Cookie.Cookie_Jar := Web.Cookie.Parse (Web.Request.Header (Request, "Cookie"));
            Id  : constant String := Web.Cookie.Value (Jar, "wf_session");
         begin
            if Web.Security.Is_Valid_Session_Id (Id) then
               return Id;
            end if;
         end;
      end if;

      return "";
   end Cookie_Id;

   function Find_Or_Create_Session (Request : Web.Request.Request_Type) return String is
      Id : constant String := Cookie_Id (Request);
   begin
      if Id'Length > 0 and then Store.Exists (Id) then
         Store.Touch (Id);
         return Id;
      end if;

      for Attempt in 1 .. 16 loop
         declare
            New_Id  : constant String := Web.Security.New_Session_Id;
            Created : Boolean;
         begin
            Store.Create (New_Id, Created);
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
      if Id'Length > 0 and then Store.Exists (Id) then
         Store.Touch (Id);
         return Id;
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
            Secure    => Store.Secure_Cookies,
            Same_Site => Web.Cookie.Lax,
            Max_Age   => -1));
   end Session_Cookie_Header;

   function Html_Response (Session : String; Content : String) return Web.Response.Response_Type is
      Response : Web.Response.Response_Type := Web.Response.Html (Content);
   begin
      Web.Response.Set_Header (Response, "Set-Cookie", Session_Cookie_Header (Session));
      return Response;
   end Html_Response;

   procedure Configure (Config : Web.Config.Config_Type) is
   begin
      if Config.Max_WebSocket_Message = 0 then
         raise Web.Errors.Security_Error with "max websocket message must be positive";
      end if;

      Store.Set_Secure_Cookies (Config.Secure_Cookies);
      Store.Set_Timeout (Config.Session_Timeout);
      Store.Set_Max_WebSocket_Message (Config.Max_WebSocket_Message);
   end Configure;

   procedure Set_Secure_Cookies (Enabled : Boolean) is
   begin
      Store.Set_Secure_Cookies (Enabled);
   end Set_Secure_Cookies;

   function Secure_Cookies return Boolean is
   begin
      return Store.Secure_Cookies;
   end Secure_Cookies;

   procedure With_State (Id : String; Process : State_Process) is
   begin
      Store.Ensure (Id);
      Store.Process (Id, Process);
   end With_State;

   procedure Set_Session_Timeout (Seconds : Natural) is
   begin
      Store.Set_Timeout (Seconds);
   end Set_Session_Timeout;

   function Cleanup_Sessions return Natural is
      Removed : Natural;
      Sockets : Socket_Vectors.Vector;
   begin
      Store.Cleanup (Removed, Sockets);

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

   procedure Run_Connection
     (Conn : in out Web.Connection.Connection_Type;
      Id   : String)
   is
      Done : Boolean := False;
      Socket : constant GNAT.Sockets.Socket_Type := Web.Connection.Socket (Conn);
      Old_Socket : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
   begin
      Store.Attach_Socket (Id, Socket, Old_Socket);
      if Old_Socket /= GNAT.Sockets.No_Socket and then Old_Socket /= Socket then
         Web.Logging.Info ("replacing websocket for session " & Id);
         Close_Quietly (Old_Socket);
      end if;

      begin
         while not Done loop
            declare
               Frame : constant Web.WebSocket.Frame :=
                 Web.WebSocket.Receive_Frame (Conn, Store.Max_WebSocket_Message);
            begin
               case Frame.Frame_Type is
                  when Web.WebSocket.Text_Frame =>
                     declare
                        Event   : constant Web.Events.Event :=
                          Web.Protocol.Decode_Client_Message (Web.WebSocket.Payload (Frame));
                        Patches : Web.Patch.Patch_List;
                     begin
                        if Web.Events.Kind (Event) /= Web.Events.Hello_Event then
                           Store.Dispatch_Event (Id, Event, Patches);
                           if not Patches.Items.Is_Empty then
                              Web.WebSocket.Send_Text (Conn, Web.Protocol.Encode_Patches (Patches));
                           end if;
                        end if;
                     end;

                  when Web.WebSocket.Ping_Frame =>
                     Web.WebSocket.Send_Pong (Conn, Web.WebSocket.Payload (Frame));

                  when Web.WebSocket.Pong_Frame =>
                     null;

                  when Web.WebSocket.Close_Frame =>
                     Web.WebSocket.Send_Close (Conn);
                     Done := True;
               end case;
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

      Store.Detach_Socket (Id, Socket);
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
