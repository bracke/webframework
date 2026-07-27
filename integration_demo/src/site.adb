with Web.Html;
with Web.Cookie;

with Navigation.Routes;
with Navigation.Menu;
with Navigation.Breadcrumbs;

with Forms.Form;
with Forms.Fields;
with Forms.Submission;
with Forms.Urlencoded;
with Forms.Binding;
with Forms.CSRF;

with Representation.Diagnostics;

with Webframework_Navigation;
with Webframework_Forms;

package body Site is

   package WN renames Webframework_Navigation;
   package WF renames Webframework_Forms;
   package NR renames Navigation.Routes;
   package NM renames Navigation.Menu;
   package NB renames Navigation.Breadcrumbs;

   use type Forms.Urlencoded.Decode_Status;

   --  Built once by Setup, then read-only (immutable after Finalize) so the
   --  handlers share them safely.
   Routes : NR.Table (16, 512);
   Menu   : NM.Menu (16, 512);
   Form   : Forms.Form.Definition (8);

   --  The CSRF hidden-field name forms expects.
   Csrf_Field : constant String := WF.To_String (Forms.CSRF.Default_Field);

   --  Server CSRF signing key. In a real app this is a stable deployment secret
   --  loaded from a keyring/config -- NOT a literal, and NOT per-request random.
   Signing_Key : constant WF.Byte_Array :=
     WF.To_Bytes ("demo-server-csrf-signing-key-change-me");

   Session_Cookie : constant String := "sid";

   --  The session id carried by the request's session cookie ("" if none). A
   --  real app derives this from its authenticated session, not from arbitrary
   --  client input; here the GET establishes it.
   function Session_Of (Request : Web.Request.Request_Type) return String is
      Jar : constant Web.Cookie.Cookie_Jar :=
        Web.Cookie.Parse (Web.Request.Header (Request, "Cookie"));
   begin
      if Web.Cookie.Has (Jar, Session_Cookie) then
         return Web.Cookie.Value (Jar, Session_Cookie);
      else
         return "";
      end if;
   end Session_Of;

   procedure Setup is
      Added  : Boolean;
      Ignore : NM.Item_Ref;
   begin
      NR.Add (Routes, "home", "/", Added);
      NR.Add (Routes, "contact", "/contact", Added);
      NR.Add (Routes, "thanks", "/thanks", Added);
      NR.Finalize (Routes);

      NM.Add_Link (Menu, NM.No_Item, "Home", "/", Ignore);
      NM.Add_Link (Menu, NM.No_Item, "Contact", "/contact", Ignore);
      NM.Finalize (Menu);

      --  The CSRF token rides along as an extra field, so ignore unknowns
      --  rather than rejecting the whole submission.
      Forms.Form.Start (Form, Unknown => Forms.Form.Ignore);
      Forms.Form.Add_Field
        (Form, Forms.Fields.Make (WF.To_Bytes ("name"),
                                  Presence => Forms.Fields.Required), Added);
      Forms.Form.Add_Field
        (Form, Forms.Fields.Make (WF.To_Bytes ("email"),
                                  Kind     => Forms.Fields.Kind_Email,
                                  Presence => Forms.Fields.Required), Added);
      Forms.Form.Finalize (Form);
   end Setup;

   --  A minimal HTML page: chrome (menu + breadcrumbs) around the form.
   function Page
     (Request : Web.Request.Request_Type; Form_Html : String) return String
   is
      Active : constant NM.Item_Ref := WN.Active_For (Menu, Routes, Request);
      Crumbs : NB.Trail (8, 512);
   begin
      NB.Build_For_Path (Crumbs, Menu, Routes, Web.Request.Path (Request));
      return
        "<!doctype html><html><body>"
        & "<header>" & WN.Render_Menu (Menu, Routes, Active)
        & WN.Render_Breadcrumbs (Crumbs) & "</header>"
        & "<main><h1>Contact</h1>" & Form_Html & "</main>"
        & "</body></html>";
   end Page;

   --  The contact form. Sticky values re-populate inputs after a failed submit;
   --  Errors (already plain text) shows the diagnostics.
   function Contact_Form
     (Csrf_Hex : String;
      Name_V   : String := "";
      Email_V  : String := "";
      Errors   : String := "") return String
   is
   begin
      return
        "<form method=""post"" action=""/contact"">"
        & "<input type=""hidden"" name=""" & Web.Html.Escape_Attribute (Csrf_Field)
        & """ value=""" & Web.Html.Escape_Attribute (Csrf_Hex) & """>"
        & (if Errors = "" then ""
           else "<div class=""errors""><pre>" & Web.Html.Escape_Text (Errors)
                & "</pre></div>")
        & "<label>Name <input name=""name"" value="""
        & Web.Html.Escape_Attribute (Name_V) & """></label>"
        & "<label>Email <input name=""email"" value="""
        & Web.Html.Escape_Attribute (Email_V) & """></label>"
        & "<button type=""submit"">Send</button>"
        & "</form>";
   end Contact_Form;

   --  Render the page for a given session, embedding a session-bound CSRF token.
   function Render_Page
     (Request : Web.Request.Request_Type;
      Sid     : String;
      Name_V  : String := "";
      Email_V : String := "";
      Errors  : String := "";
      Status  : Positive := 200) return Web.Response.Response_Type
   is
      Csrf_Hex : constant String :=
        WF.Token_Hex (WF.Session_Token (Signing_Key, Sid));
      Body_S : constant String :=
        Page (Request, Contact_Form (Csrf_Hex, Name_V, Email_V, Errors));
      Resp : Web.Response.Response_Type :=
        Web.Response.Create (Status, Body_S, "text/html; charset=utf-8");
   begin
      --  Establish / refresh the session cookie (HttpOnly).
      Web.Response.Set_Header
        (Resp, "Set-Cookie",
         Web.Cookie.Set_Cookie
           (Name => Session_Cookie, Value => Sid, Path => "/",
            Http_Only => True, Secure => False,
            Same_Site => Web.Cookie.Strict));
      return Resp;
   end Render_Page;

   function Contact_Get
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type
   is
      Existing : constant String := Session_Of (Request);
      Sid_Tok  : Forms.CSRF.Token;
      Ok       : Boolean;
   begin
      --  Reuse the request's session, or start one (a random id from the stack
      --  CSPRNG). The CSRF token is bound to it via Session_Token.
      if Existing /= "" then
         return Render_Page (Request, Existing);
      end if;
      WF.New_Token (Sid_Tok, Ok);
      if not Ok then
         return Web.Response.Internal_Server_Error;
      end if;
      return Render_Page (Request, WF.Token_Hex (Sid_Tok));
   end Contact_Get;

   function Contact_Post
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type
   is
      Sub    : Forms.Submission.Data (16, 4096);
      St     : Forms.Urlencoded.Decode_Status;
      Report : Representation.Diagnostics.Diagnostic_Set;
      Ok     : Boolean;
      Sid    : constant String := Session_Of (Request);
   begin
      WF.Read_Urlencoded (Request, Sub, St);
      if St /= Forms.Urlencoded.Decode_Ok then
         return Web.Response.Bad_Request;
      end if;

      --  Session-bound CSRF must match before we trust anything in the body: the
      --  token is verified against this session under the server key, so a
      --  planted cookie alone cannot forge it.
      if Sid = "" or else not WF.Verify_Session_Csrf (Sub, Signing_Key, Sid) then
         return Web.Response.Forbidden;
      end if;

      Representation.Diagnostics.Clear (Report);
      Forms.Binding.Bind (Form, Sub, Report, Ok);
      if Ok then
         --  Type-safe redirect by route name (Post/Redirect/Get).
         return WN.Redirect_To (Routes, "thanks");
      end if;

      --  Re-render sticky (same session, so the CSRF token stays valid).
      return Render_Page
        (Request, Sid,
         Name_V  => WF.Sticky (Form, Sub, WF.To_Bytes ("name")),
         Email_V => WF.Sticky (Form, Sub, WF.To_Bytes ("email")),
         Errors  => WF.Diagnostics_Text (Report),
         Status  => 400);
   end Contact_Post;

end Site;
