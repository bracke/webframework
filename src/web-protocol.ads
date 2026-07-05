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
end Web.Protocol;
