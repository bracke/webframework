with Web.Events;
with Web.Patch;

package Web.Protocol is
   Protocol_Version : constant Natural := 1;

   --  Decode a JSON client message into a typed event.
   --  @param Message JSON message.
   --  @return Typed event.
   function Decode_Client_Message (Message : String) return Web.Events.Event;

   --  Encode patch list as a JSON server message.
   --  @param Patches Patch list.
   --  @return JSON message.
   function Encode_Patches (Patches : Web.Patch.Patch_List) return String;

   --  Check if a client message contains a reconnecting flag.
   --  @param Message JSON message.
   --  @return True if message has reconnecting: true.
   function Has_Reconnecting (Message : String) return Boolean;

   --  Get the last message ID from a client message.
   --  @param Message JSON message.
   --  @return The lastMessageId value, or 0 if not present.
   function Get_Last_Message_Id (Message : String) return Natural;

   --  Check if an event requires acknowledgment.
   --  @param Event Parsed event.
   --  @return True if event has ackId.
   function Requires_Ack (Event : Web.Events.Event) return Boolean;

   --  Get the acknowledgment ID from an event.
   --  @param Event Parsed event.
   --  @return The ackId value, or empty string if not present.
   function Get_Ack_Id (Event : Web.Events.Event) return String;

   --  Get the message ID from an event.
   --  @param Event Parsed event.
   --  @return The messageId value, or empty string if not present.
   function Get_Message_Id (Event : Web.Events.Event) return String;

   --  Check if message is a ping message.
   --  @param Message JSON message.
   --  @return True if message type is "ping".
   function Is_Ping_Message (Message : String) return Boolean;

   --  Check if message is a pong message.
   --  @param Message JSON message.
   --  @return True if message type is "pong".
   function Is_Pong_Message (Message : String) return Boolean;

   --  Check if message is a server reconnect request.
   --  @param Message JSON message.
   --  @return True if message type is "server_reconnect".
   function Is_Server_Reconnect (Message : String) return Boolean;

   --  Check if message is an acknowledgment message.
   --  @param Message JSON message.
   --  @return True if message type is "ack".
   function Is_Ack_Message (Message : String) return Boolean;

   --  Get the acknowledgment ID from an ack message.
   --  @param Message JSON ack message.
   --  @return The ackId value, or empty string if not present.
   function Get_Ack_Id_From_Message (Message : String) return String;

   --  Create a ping message for connection health checks.
   --  @return JSON ping message.
   function Create_Ping_Message return String;

   --  Create a pong response message.
   --  @return JSON pong message.
   function Create_Pong_Message return String;

   --  Create an acknowledgment message for a given ackId.
   --  @param Ack_Id The acknowledgment ID.
   --  @return JSON ack message.
   function Create_Ack_Message (Ack_Id : String) return String;

   --  Create a server reconnect request message.
   --  @return JSON server reconnect message.
   function Create_Server_Reconnect_Message return String;
end Web.Protocol;
