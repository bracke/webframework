with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Unbounded;

package Web.Response is
   package Header_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => String);

   type Response_Type is private;
   type Compression_Encoding is (GZip, Deflate);

   --  Create a response.
   --  @param Status_Code HTTP status code.
   --  @param Content Response body.
   --  @param Content_Type Response content type.
   --  @return Response value.
   function Create
     (Status_Code  : Positive;
      Content      : String := "";
      Content_Type : String := "text/plain; charset=utf-8") return Response_Type;

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

   --  Return a compressed copy of a response body.
   --  @param Response Source response.
   --  @param Encoding HTTP content encoding to apply.
   --  @return Response copy with compressed body and Content-Encoding.
   function Compressed
     (Response : Response_Type;
      Encoding : Compression_Encoding) return Response_Type;

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

   --  Serialize response as HTTP/1.1 bytes.
   --  @param Response Response value.
   --  @return HTTP response text with Content-Length.
   function Serialize (Response : Response_Type) return String;

private
   type Response_Type is record
      Status_Code : Positive := 200;
      Headers     : Header_Maps.Map;
      Body_Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;
end Web.Response;
