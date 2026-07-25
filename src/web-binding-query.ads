with Ada.Strings.Unbounded;
with Web.Binding.Sources;

--  Query-string source.
--
--  Parses a raw query string (without the leading '?') into ordered name/value
--  pairs, percent-decoding both and mapping '+' to space. Order and duplicate
--  keys are preserved; empty names and empty values are kept; a malformed
--  percent escape marks that value without discarding it. Lookup returns every
--  value for a name, in request order, as Sources.Occurrences carrying the
--  parameter ordinal as its source location.
package Web.Binding.Query is

   --  The hard cap on retained pairs.
   Max_Pairs : constant := 512;

   type Query_Source is private;

   --  Parse a query string into a source.
   --  @param Query_String The query text without a leading '?'.
   --  @return The parsed source.
   function Parse (Query_String : String) return Query_Source;

   --  Every value supplied for Name, in request order.
   --  @param Source The parsed query.
   --  @param Name The parameter name (case-sensitive).
   --  @return The occurrences.
   function Lookup
     (Source : Query_Source; Name : String)
      return Web.Binding.Sources.Occurrences;

   --  The number of parsed pairs.
   --  @param Source The parsed query.
   --  @return The pair count.
   function Pair_Count (Source : Query_Source) return Natural;

   --  Whether pairs were dropped past the cap.
   --  @param Source The parsed query.
   --  @return True when truncated.
   function Truncated (Source : Query_Source) return Boolean;

private

   type Query_Pair is record
      Name    : Ada.Strings.Unbounded.Unbounded_String;
      Value   : Ada.Strings.Unbounded.Unbounded_String;
      Bad     : Boolean := False;
      Ordinal : Positive := 1;
   end record;

   type Pair_Array is array (1 .. Max_Pairs) of Query_Pair;

   type Query_Source is record
      Length   : Natural := 0;
      Overflow : Boolean := False;
      Pairs    : Pair_Array;
   end record;

end Web.Binding.Query;
