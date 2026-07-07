with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

package Web.Response is
   package Header_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => String,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Response_Type is private;
   type Compression_Encoding is (GZip, Deflate);

   --  Create a response.
   --  @param Status_Code HTTP status code in the range 100 .. 599.
   --  @param Content Response body.
   --  @param Content_Type Response content type.
   --  @return Response value.
   function Create
     (Status_Code  : Positive;
      Content      : String := "";
      Content_Type : String := "text/plain; charset=utf-8") return Response_Type;

   --  Create a file-backed response.
   --  @param Status_Code HTTP status code in the range 100 .. 599.
   --  @param Path Filesystem path to stream.
   --  @param Size File size in bytes.
   --  @param Content_Type Response content type.
   --  @return File-backed response value.
   function Create_File
     (Status_Code  : Positive;
      Path         : String;
      Size         : Natural;
      Content_Type : String := "application/octet-stream") return Response_Type;

   --  Create an HTML response.
   --  @param Content HTML body.
   --  @return HTML response.
   function Html (Content : String) return Response_Type;

   --  Create a text response.
   --  @param Content Text body.
   --  @return Text response.
   function Text (Content : String) return Response_Type;

   --  Create a 404 response.
   --  @return Not found response.
   function Not_Found return Response_Type;

   --  Create a 400 response.
   --  @return Bad request response.
   function Bad_Request return Response_Type;

   --  Create a 406 response.
   --  @return Not acceptable response.
   function Not_Acceptable return Response_Type;

   --  Create a 500 response.
   --  @return Internal server error response.
   function Internal_Server_Error return Response_Type;

   --  Add or replace a response header.
   --  @param Response Response to update.
   --  @param Name Header name.
   --  @param Value Header value.
   --  @return No return value.
   procedure Set_Header
     (Response : in out Response_Type;
      Name     : String;
      Value    : String);

   --  Set a stable cache key for derived response data.
   --  @param Response Response to update.
   --  @param Key Stable cache key.
   --  @return No return value.
   procedure Set_Cache_Key
     (Response : in out Response_Type;
      Key      : String);

   --  Ensure that a response Vary header contains a valid token.
   --  @param Response Response to update.
   --  @param Token Header token to include.
   --  @return No return value.
   procedure Ensure_Vary
     (Response : in out Response_Type;
      Token    : String);

   --  Return whether a response header exists.
   --  @param Response Response value.
   --  @param Name Header name.
   --  @return True when the response includes the header.
   function Has_Header
     (Response : Response_Type;
      Name     : String) return Boolean;

   --  Return a response header value.
   --  @param Response Response value.
   --  @param Name Header name.
   --  @return Header value, or an empty string when absent.
   function Header
     (Response : Response_Type;
      Name     : String) return String;

   --  Return a compressed copy of a compressible response body.
   --  @param Response Source response.
   --  @param Encoding HTTP content encoding to apply.
   --  @return Response copy with compressed body and Content-Encoding.
   function Compressed
     (Response : Response_Type;
      Encoding : Compression_Encoding) return Response_Type;

   --  Return a compressed copy using an explicit zlib compression level.
   --  @param Response Source response.
   --  @param Encoding HTTP content encoding to apply.
   --  @param Level Compression level in the range 0 .. 9.
   --  @return Response copy with compressed body and Content-Encoding.
   function Compressed
     (Response : Response_Type;
      Encoding : Compression_Encoding;
      Level    : Natural) return Response_Type;

   --  Return whether automatic HTTP compression is suitable for this response.
   --  @param Response Response value.
   --  @return True when the content type is text-like and not already encoded.
   function Is_Compressible (Response : Response_Type) return Boolean;

   --  Return response status code.
   --  @param Response Response value.
   --  @return HTTP status code.
   function Status (Response : Response_Type) return Positive;

   --  Return response body.
   --  @param Response Response value.
   --  @return Body string.
   function Content_Body (Response : Response_Type) return String;

   --  Return response body length without copying the body.
   --  @param Response Response value.
   --  @return Body length in bytes.
   function Body_Length (Response : Response_Type) return Natural;

   --  Return whether the response body is file-backed.
   --  @param Response Response value.
   --  @return True when body bytes should be streamed from a file.
   function Is_File_Body (Response : Response_Type) return Boolean;

   --  Return the file path for a file-backed response.
   --  @param Response Response value.
   --  @return Filesystem path, or an empty string for string-backed responses.
   function File_Body_Path (Response : Response_Type) return String;

   --  Serialize response as HTTP/1.1 bytes.
   --  @param Response Response value.
   --  @return HTTP response text with Content-Length.
   function Serialize (Response : Response_Type) return String;

   --  Precompute and cache the current serialized response form.
   --  @param Response Response to update.
   --  @return No return value.
   procedure Freeze_Serialized (Response : in out Response_Type);

private
   type Entity_Mode is (String_Entity, File_Entity);

   type Response_Type is record
      Status_Code : Positive := 200;
      Headers     : Header_Maps.Map;
      Mode        : Entity_Mode := String_Entity;
      Body_Value  : Ada.Strings.Unbounded.Unbounded_String;
      File_Path_Value : Ada.Strings.Unbounded.Unbounded_String;
      File_Size_Value : Natural := 0;
      Serialized_Value : Ada.Strings.Unbounded.Unbounded_String;
      Cache_Key_Value  : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type_Header     : Ada.Strings.Unbounded.Unbounded_String;
      Cache_Control_Header    : Ada.Strings.Unbounded.Unbounded_String;
      Content_Encoding_Header : Ada.Strings.Unbounded.Unbounded_String;
      Vary_Header             : Ada.Strings.Unbounded.Unbounded_String;
      Connection_Header       : Ada.Strings.Unbounded.Unbounded_String;
      Set_Cookie_Header       : Ada.Strings.Unbounded.Unbounded_String;
      Has_Content_Type     : Boolean := False;
      Has_Cache_Control    : Boolean := False;
      Has_Content_Encoding : Boolean := False;
      Has_Vary             : Boolean := False;
      Has_Connection       : Boolean := False;
      Has_Set_Cookie       : Boolean := False;
      Has_Serialized       : Boolean := False;
      Has_Cache_Key        : Boolean := False;
   end record;
end Web.Response;
