with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

package Web.Request is
   package Header_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => String,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Request_Type is private;

   --  Internal header category used by fast header insertion paths.
   type Header_Kind is
     (Unknown_Header,
      Host_Header,
      Cookie_Header,
      Connection_Header,
      Upgrade_Header,
      Accept_Encoding_Header,
      Content_Length_Header,
      Content_Type_Header,
      Transfer_Encoding_Header,
      Content_Encoding_Header,
      Expect_Header,
      Sec_WebSocket_Key_Header,
      Sec_WebSocket_Version_Header);

   --  Determine the cached header kind for a header name.
   --  @param Name Header name.
   --  @return Header category.
   function Header_Kind_Of (Name : String) return Header_Kind;
   pragma Inline (Header_Kind_Of);

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

   --  Add a header when it is not already present.
   --  @param Request Request to update.
   --  @param Name Header name.
   --  @param Value Header value.
   --  @return True when the header was added, False when it already existed.
   function Add_Header
     (Request : in out Request_Type;
      Name    : String;
      Value   : String) return Boolean;

   --  Add a pre-validated header when it is not already present.
   --  @param Request Request to update.
   --  @param Name Header name. Caller must validate header name and value.
   --  @param Value Header value. Caller must validate header name and value.
   --  @return True when the header was added, False when it already existed.
   function Add_Validated_Header
     (Request : in out Request_Type;
      Name    : String;
      Value   : String) return Boolean;

   --  Add a pre-validated header when it is not already present.
   --  @param Request Request to update.
   --  @param Kind Header category.
   --  @param Name Header name.
   --  @param Value Header value.
   --  @return True when the header was added, False when it already existed.
   function Add_Validated_Header
     (Request : in out Request_Type;
      Kind    : Header_Kind;
      Name    : String;
      Value   : String) return Boolean;

   --  Return the request method.
   --  @param Request Request value.
   --  @return HTTP method.
   function Method (Request : Request_Type) return String;

   --  Process the request method without exposing a return-copy API to callers.
   --  @param Request Request value.
   --  @return No return value.
   generic
      with procedure Process (Value : String);
   procedure With_Method (Request : Request_Type);

   --  Check whether the request method matches a value.
   --  @param Request Request value.
   --  @param Method_Name HTTP method to compare.
   --  @return True when the method matches exactly.
   function Method_Is
     (Request     : Request_Type;
      Method_Name : String) return Boolean;

   --  Return the request path.
   --  @param Request Request value.
   --  @return Request path.
   function Path (Request : Request_Type) return String;

   --  Check whether the request path matches a value.
   --  @param Request Request value.
   --  @param Path_Value Request path to compare.
   --  @return True when the path matches exactly.
   function Path_Is
     (Request    : Request_Type;
      Path_Value : String) return Boolean;

   --  Process the request path without exposing a return-copy API to callers.
   --  @param Request Request value.
   --  @return No return value.
   generic
      with procedure Process (Value : String);
   procedure With_Path (Request : Request_Type);

   --  Return the request query string.
   --  @param Request Request value.
   --  @return Query string without question mark.
   function Query_String (Request : Request_Type) return String;

   --  Process the request query string without exposing a return-copy API to callers.
   --  @param Request Request value.
   --  @return No return value.
   generic
      with procedure Process (Value : String);
   procedure With_Query_String (Request : Request_Type);

   --  Check whether a request header exists.
   --  @param Request Request value.
   --  @param Name Header name.
   --  @return True when the header exists.
   function Has_Header (Request : Request_Type; Name : String) return Boolean;

   --  Check whether a request header exists using a cached header category.
   --  @param Request Request value.
   --  @param Kind Cached header category.
   --  @return True when the cached header exists.
   function Has_Header
     (Request : Request_Type;
      Kind    : Header_Kind) return Boolean;
   pragma Inline (Has_Header);

   --  Return a request header value.
   --  @param Request Request value.
   --  @param Name Header name.
   --  @return Header value or an empty string.
   function Header (Request : Request_Type; Name : String) return String;

   --  Return a request header value using a cached header category.
   --  @param Request Request value.
   --  @param Kind Cached header category.
   --  @return Header value or an empty string.
   function Header (Request : Request_Type; Kind : Header_Kind) return String;
   pragma Inline (Header);

   --  Process a request header without exposing a return-copy API to callers.
   --  @param Request Request value.
   --  @param Name Header name.
   --  @return No return value.
   generic
      with procedure Process (Value : String);
   procedure With_Header
     (Request : Request_Type;
      Name    : String);

   --  Return the request body.
   --  @param Request Request value.
   --  @return Body string.
   function Request_Body (Request : Request_Type) return String;

   --  Process the request body without exposing a return-copy API to callers.
   --  @param Request Request value.
   --  @return No return value.
   generic
      with procedure Process (Value : String);
   procedure With_Body (Request : Request_Type);

private
   type Request_Type is record
      Method_Value : Ada.Strings.Unbounded.Unbounded_String;
      Path_Value   : Ada.Strings.Unbounded.Unbounded_String;
      Query_Value  : Ada.Strings.Unbounded.Unbounded_String;
      Body_Value   : Ada.Strings.Unbounded.Unbounded_String;
      Headers      : Header_Maps.Map;
      Host_Header                 : Ada.Strings.Unbounded.Unbounded_String;
      Cookie_Header               : Ada.Strings.Unbounded.Unbounded_String;
      Connection_Header           : Ada.Strings.Unbounded.Unbounded_String;
      Upgrade_Header              : Ada.Strings.Unbounded.Unbounded_String;
      Accept_Encoding_Header      : Ada.Strings.Unbounded.Unbounded_String;
      Content_Length_Header       : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type_Header         : Ada.Strings.Unbounded.Unbounded_String;
      Sec_WebSocket_Key_Header    : Ada.Strings.Unbounded.Unbounded_String;
      Sec_WebSocket_Version_Header : Ada.Strings.Unbounded.Unbounded_String;
      Has_Host                 : Boolean := False;
      Has_Cookie               : Boolean := False;
      Has_Connection           : Boolean := False;
      Has_Upgrade              : Boolean := False;
      Has_Accept_Encoding      : Boolean := False;
      Has_Content_Length       : Boolean := False;
      Has_Content_Type         : Boolean := False;
      Has_Sec_WebSocket_Key    : Boolean := False;
      Has_Sec_WebSocket_Version : Boolean := False;
   end record;
end Web.Request;
