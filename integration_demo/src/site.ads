with Web.Request;
with Web.Response;

--  The demo "site": a route table, a menu, and a contact-form definition built
--  once, plus two handlers that wire navigation and forms into webframework.
--
--  GET  /contact renders the page (menu with active highlighting, breadcrumbs,
--       and a CSRF-protected form).
--  POST /contact verifies CSRF, decodes + binds the submission, re-renders the
--       form sticky with errors on failure, and redirects by route name on
--       success.
package Site is

   procedure Setup;

   function Contact_Get
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   function Contact_Post
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

end Site;
