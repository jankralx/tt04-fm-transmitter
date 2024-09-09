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

# init SPI
spi = machine.SoftSPI(100000, sck=25, mosi=27, miso=28)
cs = machine.Pin(26, machine.Pin.OUT)

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
