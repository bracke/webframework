with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Unbounded;

package Web.Request is
   package Header_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => String);

   type Request_Type is private;

   --  Create a request value from parsed HTTP parts.
   --  @param Method_Name HTTP method.
   --  @param Path_Value Request path.
   --  @param Query_Value Request query string without question mark.
   --  @param Body_Value Request body.
   --  @return Request value.
   function Create
     (Method_Name : String;
      Path_Value  : String;
      Query_Value : String := "";
      Body_Value  : String := "") return Request_Type;

   --  Add or replace a header.
   --  @param Request Request to update.
   --  @param Name Header name.
   --  @param Value Header value.
   --  @return No return value.
   procedure Set_Header
     (Request : in out Request_Type;
      Name    : String;
      Value   : String);

   --  Return the request method.
   --  @param Request Request value.
   --  @return HTTP method.
   function Method (Request : Request_Type) return String;

   --  Return the request path.
   --  @param Request Request value.
   --  @return Request path.
   function Path (Request : Request_Type) return String;

   --  Return the request query string.
   --  @param Request Request value.
   --  @return Query string without question mark.
   function Query_String (Request : Request_Type) return String;

   --  Check whether a request header exists.
   --  @param Request Request value.
   --  @param Name Header name.
   --  @return True when the header exists.
   function Has_Header (Request : Request_Type; Name : String) return Boolean;

   --  Return a request header value.
   --  @param Request Request value.
   --  @param Name Header name.
   --  @return Header value or an empty string.
   function Header (Request : Request_Type; Name : String) return String;

   --  Return the request body.
   --  @param Request Request value.
   --  @return Body string.
   function Request_Body (Request : Request_Type) return String;

private
   type Request_Type is record
      Method_Value : Ada.Strings.Unbounded.Unbounded_String;
      Path_Value   : Ada.Strings.Unbounded.Unbounded_String;
      Query_Value  : Ada.Strings.Unbounded.Unbounded_String;
      Body_Value   : Ada.Strings.Unbounded.Unbounded_String;
      Headers      : Header_Maps.Map;
   end record;
end Web.Request;
