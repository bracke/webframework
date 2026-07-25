with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 1 tests for the temporal and numeric/binary decoders: ISO date (incl.
--  the impossible-date case), time, RFC 3339 date-time, modular integer, float
--  (incl. non-finite), and Base64.
package Web_Binding_Decoder_Ext_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the extended decoder tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  ISO date: valid, impossible (2026-02-31), leap-year edges, bad format.
   --  @param Item AUnit fixture.
   procedure Test_Date (Item : in out Fixture);

   --  Time of day: fields, fractional seconds, range, leap second.
   --  @param Item AUnit fixture.
   procedure Test_Time (Item : in out Fixture);

   --  RFC 3339 date-time: Z and numeric offsets, fractions, bad instants.
   --  @param Item AUnit fixture.
   procedure Test_DateTime (Item : in out Fixture);

   --  Modular integer: value, out of range, radix.
   --  @param Item AUnit fixture.
   procedure Test_Modular (Item : in out Fixture);

   --  Float: values, invalid syntax, non-finite words.
   --  @param Item AUnit fixture.
   procedure Test_Float (Item : in out Fixture);

   --  Base64: decode, padding policy, invalid alphabet.
   --  @param Item AUnit fixture.
   procedure Test_Base64 (Item : in out Fixture);

end Web_Binding_Decoder_Ext_Tests;
