package body Web.Context is

   use Ada.Strings.Unbounded;

   function New_Context return Request_Context is
      Ctx : Request_Context;
   begin
      return Ctx;
   end New_Context;

   function Session (Ctx : Request_Context) return String is
   begin
      return To_String (Ctx.Session_Value);
   end Session;

   procedure Set_Session (Ctx : in out Request_Context; Id : String) is
   begin
      Ctx.Session_Value := To_Unbounded_String (Id);
   end Set_Session;

   function Has_Principal (Ctx : Request_Context) return Boolean is
   begin
      return Ctx.Principal_Present;
   end Has_Principal;

   function Principal (Ctx : Request_Context) return String is
   begin
      return To_String (Ctx.Principal_Value);
   end Principal;

   procedure Set_Principal (Ctx : in out Request_Context; Value : String) is
   begin
      Ctx.Principal_Value := To_Unbounded_String (Value);
      Ctx.Principal_Present := True;
   end Set_Principal;

   procedure Clear_Principal (Ctx : in out Request_Context) is
   begin
      Ctx.Principal_Value := Null_Unbounded_String;
      Ctx.Principal_Present := False;
   end Clear_Principal;

   procedure Set_Attribute
     (Ctx   : in out Request_Context;
      Key   : String;
      Value : String) is
   begin
      Ctx.Attributes.Include (Key, Value);
   end Set_Attribute;

   function Has_Attribute (Ctx : Request_Context; Key : String) return Boolean is
   begin
      return Ctx.Attributes.Contains (Key);
   end Has_Attribute;

   function Attribute (Ctx : Request_Context; Key : String) return String is
   begin
      if Ctx.Attributes.Contains (Key) then
         return Ctx.Attributes.Element (Key);
      end if;
      return "";
   end Attribute;

end Web.Context;
