/*
  These are all the functions that make the MMA8452 tick
*/
// The SparkFun breakout board defaults to 1, set to 0 if SA0 jumper on the bottom of the board is set
#define MMA8452_ADDRESS 0x1D  // 0x1D if SA0 is high, 0x1C if low

//Define a few of the registers that we will be accessing on the MMA8452
#define OUT_X_MSB 0x01
#define XYZ_DATA_CFG  0x0E
#define WHO_AM_I   0x0D
#define CTRL_REG1  0x2A

#define GSCALE 4 // Sets full-scale range to +/-2, 4, or 8g. Used to calc real g values.

#define MAXTIME 100 //Number of milliseconds before we give up
#define TIMEOUT_ERROR 255 //Return 255 on the case of error. Should work for functions that return bytes


//Checks the accelerometer and converts the readings to actual g values
//Returns an array containing the float values.
float getAccelData()
{
  int accelCount[3];  // Stores the 12-bit signed value
  readAccelData(accelCount);  // Read the x/y/z adc values
  
  /*Serial.print(" ");
  Serial.print(accelCount[0]);
  Serial.print(" ");
  Serial.print(accelCount[1]);
  Serial.print(" ");
  Serial.print(accelCount[2]);
  delay(10);
  Serial.println();*/
  
  // Now we'll calculate the accleration value into actual g's
  /*float accelG[3]; // Stores the accel values in G form
  for (int i = 0 ; i < 3 ; i++)
    accelG[i] = (float) accelCount[i] / ((1<<12)/(2*GSCALE));  // get actual g value, this depends on scale being set

  //Now calculate the overall magnitude of the combined vectors
  float mag = sqrt( pow(accelG[0], 2) + pow(accelG[1], 2) + pow(accelG[2], 2));*/

  //Calculate the overall magnitude of just the regular readings
  float mag = sqrt( pow(accelCount[0], 2) + pow(accelCount[1], 2) + pow(accelCount[2], 2));
  
  return(mag);
}

void readAccelData(int *destination)
{
  byte rawData[6];  // x/y/z accel register data stored here

  if(readRegisters(OUT_X_MSB, 6, rawData) == TIMEOUT_ERROR)  // Read the six raw data registers into data array
  {
    //Restart the accel
    Serial.println("Restarting accel communication");
    while(readRegisters(OUT_X_MSB, 6, rawData) == TIMEOUT_ERROR)
    {
      initMMA8452(); //Test and intialize the MMA8452
    }

    //Reset global vars
    lastPrint = millis();
    lastHitTime = millis();
    
    lastMagnitude = 0;
    lastFirstPass = 0;
    lastSecondPass = 0;
    lastThirdPass = 0;
  }

  // Loop to calculate 12-bit ADC and g value for each axis
  for(int i = 0; i < 3 ; i++)
  {
    int gCount = (rawData[i*2] << 8) | rawData[(i*2)+1];  //Combine the two 8 bit registers into one 12-bit number
    gCount >>= 4; //The registers are left align, here we right align the 12-bit integer

    // If the number is negative, we have to make it so manually (no 12-bit data type)
    if (rawData[i*2] > 0x7F)
    {  
      gCount = ~gCount + 1;
      gCount *= -1;  // Transform into negative 2's complement #
    }

    destination[i] = gCount; //Record this gCount into the 3 int array
  }
}

// Initialize the MMA8452 registers 
// See the many application notes for more info on setting all of these registers:
// http://www.freescale.com/webapp/sps/site/prod_summary.jsp?code=MMA8452Q
void initMMA8452()
{
  wdt_reset(); //Pet the dog
  
  //TWBR = 400000L; //Set I2C to run at 400kHz
  Wire.begin(); //Join the bus as a master

  byte c = readRegister(WHO_AM_I);  // Read WHO_AM_I register
  if (c == 0x2A) // WHO_AM_I should always be 0x2A
  {  
    Serial.println("MMA8452Q is online...");
  }
  else
  {
    Serial.println("Could not connect to MMA8452Q");
    return;
  }

  MMA8452Standby();  // Must be in standby to change registers

  // Set up the full scale range to 2, 4, or 8g.
  byte fsr = GSCALE;
  if(fsr > 8) fsr = 8; //Easy error check
  fsr >>= 2; // Neat trick, see page 22. 00 = 2G, 01 = 4A, 10 = 8G
  writeRegister(XYZ_DATA_CFG, fsr);

  //The default data rate is 800Hz and we don't modify it in this example code

  MMA8452Active();  // Set to active to start reading
}

// Sets the MMA8452 to standby mode. It must be in standby to change most register settings
void MMA8452Standby()
{
  byte c = readRegister(CTRL_REG1);
  writeRegister(CTRL_REG1, c & ~(0x01)); //Clear the active bit to go into standby
}

// Sets the MMA8452 to active mode. Needs to be in this mode to output data
void MMA8452Active()
{
  byte c = readRegister(CTRL_REG1);
  writeRegister(CTRL_REG1, c | 0x01); //Set the active bit to begin detection
}

// Read bytesToRead sequentially, starting at addressToRead into the dest byte array
byte readRegisters(byte addressToRead, int bytesToRead, byte * dest)
{
  wdt_reset(); //Pet the dog
  
  Wire.beginTransmission(MMA8452_ADDRESS);
  Wire.write(addressToRead);
  Wire.endTransmission(false); //endTransmission but keep the connection active

  Wire.requestFrom(MMA8452_ADDRESS, bytesToRead); //Ask for bytes, once done, bus is released by default

  long startTime = millis();  
  while(Wire.available() < bytesToRead) //Hang out until we get the # of bytes we expect
  {
    if(millis() - startTime > MAXTIME) return(TIMEOUT_ERROR);
  }

  for(int x = 0 ; x < bytesToRead ; x++)
    dest[x] = Wire.read();    
}

// Read a single byte from addressToRead and return it as a byte
byte readRegister(byte addressToRead)
{
  wdt_reset(); //Pet the dog
  
  Wire.beginTransmission(MMA8452_ADDRESS);
  Wire.write(addressToRead);
  Wire.endTransmission(false); //endTransmission but keep the connection active

  Wire.requestFrom(MMA8452_ADDRESS, 1); //Ask for 1 byte, once done, bus is released by default

  long startTime = millis();
  while(!Wire.available()) //Wait for the data to come back
  {
    if(millis() - startTime > MAXTIME) return(TIMEOUT_ERROR);    
  }
  
  return Wire.read(); //Return this one byte
}

// Writes a single byte (dataToWrite) into addressToWrite
void writeRegister(byte addressToWrite, byte dataToWrite)
{
  Wire.beginTransmission(MMA8452_ADDRESS);
  Wire.write(addressToWrite);
  Wire.write(dataToWrite);
  Wire.endTransmission(); //Stop transmitting
}
