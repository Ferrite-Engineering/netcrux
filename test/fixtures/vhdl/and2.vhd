-- Two-input AND gate. The simplest possible VHDL fixture:
-- one combinational signal, three single-bit ports. Mirrors the
-- Verilog and2 fixture under test/fixtures/verilog/.
library ieee;
use ieee.std_logic_1164.all;

entity and2 is
  port (
    a : in  std_logic;
    b : in  std_logic;
    y : out std_logic
  );
end entity and2;

architecture rtl of and2 is
begin
  y <= a and b;
end architecture rtl;
