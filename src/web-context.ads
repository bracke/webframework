with Ada.Strings.Unbounded;
private with Ada.Containers.Indefinite_Hashed_Maps;
private with Ada.Strings.Hash;

--  Request-scoped context threaded through the guard chain to the handler.
--
--  The framework populates nothing here by policy. Guards enrich the context
--  (resolve a session, attach a principal, stash a derived fact) and the
--  handler reads it. The principal is an opaque reference the framework never
--  interprets -- identity and authorization assign it meaning. Keeping it a
--  bare string is deliberate: the framework core depends on neither library.
package Web.Context is

   type Request_Context is private;

   --  Return a fresh, anonymous context with no session and no principal.
   function New_Context return Request_Context;

   --  The resolved session id for this request, or an empty string.
   function Session (Ctx : Request_Context) return String;

   --  Attach the resolved session id.
   procedure Set_Session (Ctx : in out Request_Context; Id : String);

   --  Whether a principal has been attached to this context.
   function Has_Principal (Ctx : Request_Context) return Boolean;

   --  The opaque principal reference, or an empty string when anonymous.
   function Principal (Ctx : Request_Context) return String;

   --  Attach an opaque principal reference; marks the context authenticated.
   procedure Set_Principal (Ctx : in out Request_Context; Value : String);

   --  Drop any attached principal, returning the context to anonymous.
   procedure Clear_Principal (Ctx : in out Request_Context);

   --  Stash a derived, framework-opaque fact for the handler, for example a
   --  tenant or assurance marker a guard computed.
   procedure Set_Attribute
     (Ctx   : in out Request_Context;
      Key   : String;
      Value : String);

   --  Whether a derived attribute is present.
   function Has_Attribute (Ctx : Request_Context; Key : String) return Boolean;

   --  A derived attribute value, or an empty string when absent.
   function Attribute (Ctx : Request_Context; Key : String) return String;

private

   package Attribute_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => String,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Request_Context is record
      Session_Value     : Ada.Strings.Unbounded.Unbounded_String;
      Principal_Value   : Ada.Strings.Unbounded.Unbounded_String;
      Principal_Present : Boolean := False;
      Attributes        : Attribute_Maps.Map;
   end record;

end Web.Context;
