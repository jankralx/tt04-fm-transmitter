import machine
import time

# Define the bit positions based on the chart
BIT_POSITIONS = {
    'ACC_INC': (0, 17),
    'DF_INC_COEF': (18, 21),
    'DF_INC_FACT': (22, 23),
    'DAC_ENA': (24, 27),
    'DITH_FACT': (28, 30),
    'MULTIPLY_SEL': (31, 31),
    'AUDIO_CHAN_SEL': (32, 32),
    'I2S_WS_ALIGN': (33, 33),
    'SPI_OVERRIDE': (34, 34)
}

def decode_spi_config(byte_array):
    # Convert byte array to integer
    spi_latch = 0
    for b in byte_array:
        spi_latch = (spi_latch << 8) | b
    
    # bit shift by 4 bits to get the actual value
    spi_latch >>= 4
    
    decoded_values = {}
    
    #
    # Extract and decode each value from the spi_latch register
    for key, (lsb, msb) in BIT_POSITIONS.items():
        mask = (1 << (msb - lsb + 1)) - 1
        decoded_values[key] = (spi_latch >> lsb) & mask
    #
    return decoded_values

def encode_spi_config(config):
    # Initialize the spi_latch variable
    spi_latch = 0
    
    # Encode each value into the spi_latch register
    for key, (lsb, msb) in BIT_POSITIONS.items():
        value = config.get(key, 0)
        spi_latch |= (value & ((1 << (msb - lsb + 1)) - 1)) << lsb
    
    # Convert the integer spi_latch to a byte array
    byte_array = bytearray()
    while spi_latch:
        byte_array = bytearray([spi_latch & 0xFF]) + byte_array
        spi_latch >>= 8
    
    return byte_array


def init_design():
    # design control pins
    pin_clk = machine.Pin(0, machine.Pin.OUT)
    pin_nrst = machine.Pin(1, machine.Pin.OUT)
    
    # design selection pins
    pin_sel_ena = machine.Pin(6, machine.Pin.OUT)
    pin_sel_nrst = machine.Pin(7, machine.Pin.OUT)
    pin_sel_inc = machine.Pin(8, machine.Pin.OUT)

    # select the FM modulator design
    design_id = 195
    pin_nrst(0) # keep the selected design in reset
    pin_sel_ena(0) # disable current design
    pin_sel_inc(0) # reset increment pin state
    pin_sel_nrst(0) # reset design selection counter
    time.sleep(0.001)# reset design selection counter
    pin_sel_nrst(1) # reset design selection counter
    time.sleep(0.001)# reset design selection counter
    
    # increment the selection counter
    for _ in range(design_id):
        pin_sel_inc(1)
        time.sleep(0.001)
        pin_sel_inc(0)
        time.sleep(0.001)
        
    # enable the design
    pin_sel_ena(1)
    time.sleep(0.001)
    
    # design clock generation
    pwm = machine.PWM(pin_clk, freq=int(50e6), duty_u16=32768)
    time.sleep(0.001)
    
    # let the design run
    pin_nrst(0)
    time.sleep(0.001)


if __name__ == "__main__":
    # init SPI and the design in TT04
    spi = machine.SPI(0, baudrate=100000, sck=18, mosi=19, miso=16)
    cs = machine.Pin(17, machine.Pin.OUT)
    
    init_design()    

    # modulator configuration values
    wr_cfg = {
        'ACC_INC': 52429,
        'DF_INC_FACT': 0,
        'MULTIPLY_SEL': 0, 
        'DITH_FACT': 2, 
        'SPI_OVERRIDE': 1, 
        'I2S_WS_ALIGN': 0, 
        'AUDIO_CHAN_SEL': 0, 
        'DF_INC_COEF': 12, 
        'DAC_ENA': 15
    }

    # write and read SPI config
    cs(0)
    rd_cfg = bytearray(5)
    spi.write_readinto(encode_spi_config(wr_cfg), rd_cfg)
    print(decode_spi_config(rd_cfg))
    cs(1)

    time.sleep(0.1)

    cs(0)
    rd_cfg = bytearray(5)
    spi.write_readinto(encode_spi_config(wr_cfg), rd_cfg)
    print(decode_spi_config(rd_cfg))
    cs(1)
