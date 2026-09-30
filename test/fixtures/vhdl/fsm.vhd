-- Simple two-state FSM. VHDL counterpart to test/fixtures/verilog/fsm.v.
-- One synchronous register, one combinational next-state mux. Yosys
-- via the GHDL plugin lowers this to a register + comb logic; the
-- round-trip test asserts the module + port shape rather than the
-- exact cell library Yosys infers.
library ieee;
use ieee.std_logic_1164.all;

entity fsm is
  port (
    clk    : in  std_logic;
    rst_n  : in  std_logic;
    go     : in  std_logic;
    busy   : out std_logic
  );
end entity fsm;

architecture rtl of fsm is
  type state_t is (s_idle, s_run);
  signal state, next_state : state_t;
begin

  -- State register.
  process (clk, rst_n)
  begin
    if rst_n = '0' then
      state <= s_idle;
    elsif rising_edge(clk) then
      state <= next_state;
    end if;
  end process;

  -- Next-state logic.
  process (state, go)
  begin
    case state is
      when s_idle =>
        if go = '1' then
          next_state <= s_run;
        else
          next_state <= s_idle;
        end if;
      when s_run =>
        next_state <= s_idle;
    end case;
  end process;

  -- Output: busy when in s_run.
  busy <= '1' when state = s_run else '0';

end architecture rtl;
