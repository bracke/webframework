with Web.Request;
with Web.Binding.Sources;

--  Header source.
--
--  Looks up a request header by name. This framework stores a single value per
--  header name, so a present header yields exactly one occurrence; raw repeated
--  header lines are not preserved by the transport (a future enhancement).
--  Comma-combined headers are left intact for a header-specific decoder to split
--  explicitly -- values are never blindly joined or split here.
package Web.Binding.Headers is

   --  Whether the request carries the named header.
   --  @param Request The request.
   --  @param Name The header name.
   --  @return True when present.
   function Has (Request : Web.Request.Request_Type; Name : String)
      return Boolean;

   --  The header value as occurrences (zero or one).
   --  @param Request The request.
   --  @param Name The header name.
   --  @return The occurrences.
   function Lookup
     (Request : Web.Request.Request_Type; Name : String)
      return Web.Binding.Sources.Occurrences;

end Web.Binding.Headers;
