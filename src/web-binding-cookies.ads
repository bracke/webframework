with Web.Cookie;
with Web.Binding.Sources;

--  Cookie source.
--
--  Looks up a cookie from a parsed jar. The framework jar reports how many times
--  a name occurred but keeps a single value, so a duplicated cookie is surfaced
--  as that many occurrences of the same value -- enough for the default Reject
--  duplicate policy to fire (BIND-007) while Require_Identical still passes.
package Web.Binding.Cookies is

   --  The cookie value as occurrences (one per reported duplicate).
   --  @param Jar The parsed cookie jar.
   --  @param Name The cookie name.
   --  @return The occurrences.
   function Lookup
     (Jar : Web.Cookie.Cookie_Jar; Name : String)
      return Web.Binding.Sources.Occurrences;

end Web.Binding.Cookies;
