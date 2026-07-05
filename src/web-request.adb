with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Web.Request is
   use Ada.Strings.Unbounded;

   function Header_Key (Name : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Name);
   end Header_Key;

   function Create
     (Method_Name : String;
      Path_Value  : String;
      Query_Value : String := "";
      Body_Value  : String := "") return Request_Type
   is
   begin
      return
        (Method_Value => To_Unbounded_String (Method_Name),
         Path_Value   => To_Unbounded_String (Path_Value),
         Query_Value  => To_Unbounded_String (Query_Value),
         Body_Value   => To_Unbounded_String (Body_Value),
         Headers      => Header_Maps.Empty_Map);
   end Create;

   procedure Set_Header
     (Request : in out Request_Type;
      Name    : String;
      Value   : String) is
   begin
      Request.Headers.Include (Header_Key (Name), Value);
   end Set_Header;

   function Method (Request : Request_Type) return String is
   begin
      return To_String (Request.Method_Value);
   end Method;

   function Path (Request : Request_Type) return String is
   begin
      return To_String (Request.Path_Value);
   end Path;

   function Query_String (Request : Request_Type) return String is
   begin
      return To_String (Request.Query_Value);
   end Query_String;

   function Has_Header (Request : Request_Type; Name : String) return Boolean is
   begin
      return Request.Headers.Contains (Header_Key (Name));
   end Has_Header;

   function Header (Request : Request_Type; Name : String) return String is
      Key : constant String := Header_Key (Name);
   begin
      if Request.Headers.Contains (Key) then
         return Request.Headers.Element (Key);
      end if;

      return "";
   end Header;

   function Request_Body (Request : Request_Type) return String is
   begin
      return To_String (Request.Body_Value);
   end Request_Body;
end Web.Request;
