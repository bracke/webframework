with Web.Response;
with Web.Http_Body;

with Webfiles;

--  Attachments feature: file upload / list / download / delete, backed by the
--  webfiles / webuploads subsystem. This package concentrates all webfiles wiring
--  -- it composes the service (durable local storage + an in-memory metadata
--  repository + the shared production clock and CSPRNG), and owns an in-memory
--  catalog mapping small attachment numbers to committed object references. The
--  application owns the catalog; webfiles owns the bytes. Object ids and storage
--  keys never leave this package or appear in a URL.
--
--  The page handlers in App.Pages stay thin: they resolve the session, check
--  CSRF, and call these operations.
package App.Attachments is

   type Init_Status is (Ready, Storage_Error, Service_Error);

   --  Compose the service over a durable store rooted at Data_Root (created if
   --  absent). Idempotent per process; safe to call once at startup.
   procedure Initialize (Data_Root : String; Status : out Init_Status);

   Max_Attachments : constant := 256;

   type Doc_Number is new Positive;

   type Entry_View is record
      Number : Doc_Number := 1;
      Name   : String (1 .. 128) := [others => ' '];
      Name_Length : Natural := 0;
      Size   : Webfiles.Byte_Count := 0;
   end record;

   type Entry_Array is array (Positive range <>) of Entry_View;

   --  A snapshot of the current attachments, oldest first.
   procedure List (Items : out Entry_Array; Count : out Natural);

   --  Stream a multipart upload straight into storage (no whole-file buffering),
   --  commit it, and add it to the catalog. Boundary comes from the request's
   --  Content-Type. Ok is False when no usable file was found or the commit
   --  failed. This is the large-upload path.
   procedure Stream_Upload
     (Body_R   : in out Web.Http_Body.Reader;
      Boundary : String;
      Ok       : out Boolean);

   --  Stream a stored attachment as an HTTP attachment, or a not-found response.
   function Download (Number : Doc_Number) return Web.Response.Response_Type;

   --  Remove an attachment (two-phase delete + drop from the catalog).
   procedure Delete (Number : Doc_Number);

end App.Attachments;
