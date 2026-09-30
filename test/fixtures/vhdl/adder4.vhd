-- 4-bit combinational adder. VHDL counterpart to test/fixtures/verilog/
-- adder4.v. The Yosys-via-GHDL elaboration produces an adder-shaped
-- structural netlist that the round-trip test asserts on by module
-- and port name (cell shape is structurally equivalent but
-- semantically free for the GHDL plugin to lower as it sees fit).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adder4 is
  port (
    a    : in  std_logic_vector(3 downto 0);
    b    : in  std_logic_vector(3 downto 0);
    sum  : out std_logic_vector(4 downto 0)
  );
end entity adder4;

architecture rtl of adder4 is
begin
  sum <= std_logic_vector(
    resize(unsigned(a), 5) + resize(unsigned(b), 5)
  );
end architecture rtl;
