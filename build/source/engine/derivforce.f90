! SUMMA - Structure for Unifying Multiple Modeling Alternatives
! Copyright (C) 2014-2015 NCAR/RAL
!
! This file is part of SUMMA
!
! For more information see: http://www.ral.ucar.edu/projects/summa
!
! This program is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

module derivforce_module
USE nrtype
! look-up values for the choice of snow albedo options
USE mDecisions_module,only:  &
 constDens,              &    ! Constant new snow density
 anderson,               &    ! Anderson 1976
 hedAndPom,              &    ! Hedstrom and Pomeroy (1998), expoential increase
 pahaut_76                    ! Pahaut 1976, wind speed dependent (derived from Col de Porte, French Alps)
implicit none
private
public::derivforce
contains


 ! ************************************************************************************************
 ! public subroutine derivforce: compute derived forcing data
 ! ************************************************************************************************
 subroutine derivforce(err,message)
 USE multiconst,only:Tfreeze                                 ! freezing point of pure water (K)
 USE multiconst,only:secprhour                               ! number of seconds in an hour
 USE multiconst,only:minprhour                               ! number of minutes in an hour
 USE data_struc,only:data_step                               ! length of the data step (s)
 USE data_struc,only:time_data,forc_data                     ! forcing data structures
 USE data_struc,only:attr_data,mpar_data,mvar_data           ! model data structures
 USE data_struc,only:model_decisions                         ! model decision structure
 USE var_lookup,only:iLookTIME,iLookATTR                     ! named variables for structure elements
 USE var_lookup,only:iLookPARAM,iLookFORCE,iLookMVAR         ! named variables for structure elements
 USE var_lookup,only:iLookDECISIONS                          ! named variables for elements of the decision structure
 USE sunGeomtry_module,only:clrsky_rad                       ! compute cosine of the solar zenith angle
 USE conv_funcs_module,only:vapPress                         ! compute vapor pressure of air (Pa)
 USE conv_funcs_module,only:SPHM2RELHM,RELHM2SPHM,WETBULBTMP ! conversion functions
 USE snow_utils_module,only:fracliquid,templiquid            ! functions to compute temperature/liquid water
 ! compute derived forcing data variables
 implicit none
 ! dummy variables
 integer(i4b),intent(out)      :: err                        ! error code
 character(*),intent(out)      :: message                    ! error message
 ! variables for cosine of the solar zenith angle
 integer(i4b),pointer          :: im                         ! month
 integer(i4b),pointer          :: id                         ! day
 integer(i4b),pointer          :: ih                         ! hour
 integer(i4b),pointer          :: imin                       ! minute
 real(dp)                      :: ahour                      ! hour at start of time step
 real(dp)                      :: dataStep                   ! data step (hours)
 real(dp),parameter            :: slope=0._dp                ! terrain slope (assume flat)
 real(dp),parameter            :: azimuth=0._dp              ! terrain azimuth (assume zero)
 real(dp),pointer              :: latitude                   ! latitude (degrees north)
 real(dp)                      :: hri                        ! average radiation index over time step DT
 real(dp),pointer              :: cosZenith                  ! average cosine of the zenith angle over time step DT
 ! local pointers to model parameters
 real(dp),pointer              :: Frad_vis                   ! fraction radiation absorbed in visible part of spectrum (-)
 real(dp),pointer              :: directScale                ! scaling factor for fractional driect radiaion parameterization (-)
 real(dp),pointer              :: Frad_direct                ! maximum fraction direct radiation (-)
 real(dp),pointer              :: minwind                    ! minimum windspeed (m s-1)
 real(dp),pointer              :: fc_param                   ! freezing curve parameter for snow (K-1)
 real(dp),pointer              :: tempCritRain               ! critical temperature where precipitation is rain (K)
 real(dp),pointer              :: tempRangeTimestep          ! temperature range over the time step (K)
 real(dp),pointer              :: frozenPrecipMultip         ! frozen precipitation multiplier (-)
 real(dp),pointer              :: newSnowDenMin              ! minimum new snow density (kg m-3)
 real(dp),pointer              :: newSnowDenMult             ! multiplier for new snow density (kg m-3)
 real(dp),pointer              :: newSnowDenScal             ! scaling factor for new snow density (K)
 real(dp),pointer              :: constSnowDen               ! Constant new snow density (kg m-3)
 real(dp),pointer              :: newSnowDenAdd              ! Pahaut 1976, additive factor for new snow density (kg m-3)
 real(dp),pointer              :: newSnowDenMultTemp         ! Pahaut 1976, multiplier for new snow density applied to air temperature (kg m-3 K-1)
 real(dp),pointer              :: newSnowDenMultWind         ! Pahaut 1976, multiplier for new snow density applied to wind speed (kg m-7/2 s-1/2)
 real(dp),pointer              :: newSnowDenMultAnd          ! Anderson 1976, multiplier for new snow density for Anderson function (K-1)
 real(dp),pointer              :: newSnowDenBase             ! Anderson 1976, base value that is rasied to the (3/2) power (K)
 ! local pointers to model forcing data
 real(dp),pointer              :: SWRadAtm                   ! downward shortwave radiation (W m-2)
 real(dp),pointer              :: airtemp                    ! air temperature at 2 meter height (K)
 real(dp),pointer              :: windspd                    ! wind speed at 10 meter height (m s-1)
 real(dp),pointer              :: airpres                    ! air pressure at 2 meter height (Pa)
 real(dp),pointer              :: spechum                    ! specific humidity at 2 meter height (g g-1)
 real(dp),pointer              :: pptrate                    ! precipitation rate (kg m-2 s-1)
 ! local pointers to derived model forcing data
 real(dp),pointer              :: scalarO2air                ! atmospheric o2 concentration (Pa)
 real(dp),pointer              :: scalarCO2air               ! atmospheric co2 concentration (Pa)
 ! local pointers to model variables
 real(dp),pointer              :: scalarFractionDirect       ! fraction of direct radiation (0-1)
 real(dp),pointer              :: spectralIncomingDirect(:)  ! downwelling direct shortwave radiation in each wave band (W m-2)
 real(dp),pointer              :: spectralIncomingDiffuse(:) ! downwelling diffuse shortwave radiation in each wave band (W m-2)
 real(dp),pointer              :: VPair                      ! vapor pressure of the air above the vegetation canopy (Pa)
 real(dp),pointer              :: twetbulb                   ! wet bulb temperature (K)
 real(dp),pointer              :: rainfall                   ! computed rainfall rate (kg m-2 s-1)
 real(dp),pointer              :: snowfall                   ! computed snowfall rate (kg m-2 s-1)
 real(dp),pointer              :: snowfallTemp               ! computed temperature of fresh snow (K)
 real(dp),pointer              :: newSnowDensity             ! computed density of fresh snow (kg m-3)
 ! local variables
 real(dp),parameter            :: valueMissing=-9999._dp     ! missing value
 real(dp),parameter            :: co2Factor=355.e-6_dp       ! empirical factor to obtain partial pressure of co2
 real(dp),parameter            :: o2Factor=0.209_dp          ! empirical factor to obtain partial pressure of o2
 real(dp)                      :: relhum                     ! relative humidity (-)
 real(dp)                      :: fracrain                   ! fraction of precipitation that falls as rain
 real(dp)                      :: maxFrozenSnowTemp          ! maximum temperature of snow when the snow is predominantely frozen (K)
 real(dp),parameter            :: unfrozenLiq=0.01_dp        ! unfrozen liquid water used to compute maxFrozenSnowTemp (-)
 real(dp),parameter            :: eps=epsilon(fracrain)      ! a number that is almost negligible
 real(dp)                      :: Tmin,Tmax                  ! minimum and maximum wet bulb temperature in the time step (K)
 real(dp),parameter            :: pomNewSnowDenMax=150._dp   ! Upper limit for new snow density limit in Hedstrom and Pomeroy 1998. 150 was used because at was the highest observed density at air temperatures used in this study. See Figure 4 of Hedstrom and Pomeroy (1998).
 real(dp),parameter            :: andersonWarmDenLimit=2._dp ! Upper air temperature limit in Anderson (1976) new snow density (C)
 real(dp),parameter            :: andersonColdDenLimit=15._dp! Lower air temperature limit in Anderson (1976) new snow density (C)
 real(dp),parameter            :: andersonDenScal=1.5_dp     ! Scalar parameter in Anderson (1976) new snow density function (-) 
 real(dp),parameter            :: pahautDenWindScal=0.5_dp   ! Scalar parameter for wind impacts on density using Pahaut (1976) function (-)
 ! initialize error control
 err=0; message="f-derivforce/"
 ! assign pointers to model parameters
 Frad_vis           => mpar_data%var(iLookPARAM%Frad_vis)           ! fraction radiation absorbed in visible part of spectrum (-)
 directScale        => mpar_data%var(iLookPARAM%directScale)        ! scaling factor for fractional driect radiaion parameterization (-)
 Frad_direct        => mpar_data%var(iLookPARAM%Frad_direct)        ! maximum fraction direct radiation (-)
 minwind            => mpar_data%var(iLookPARAM%minwind)            ! minimum windspeed (m s-1)
 fc_param           => mpar_data%var(iLookPARAM%snowfrz_scale)      ! freezing curve parameter for snow (K-1)
 tempCritRain       => mpar_data%var(iLookPARAM%tempCritRain)       ! critical temperature where precipitation is rain (K)
 tempRangeTimestep  => mpar_data%var(iLookPARAM%tempRangeTimestep)  ! temperature range over the time step (K)
 frozenPrecipMultip => mpar_data%var(iLookPARAM%frozenPrecipMultip) ! frozen precipitation multiplier (-)
 newSnowDenMin      => mpar_data%var(iLookPARAM%newSnowDenMin)      ! minimum new snow density (kg m-3)
 newSnowDenMult     => mpar_data%var(iLookPARAM%newSnowDenMult)     ! multiplier for new snow density (kg m-3)
 newSnowDenScal     => mpar_data%var(iLookPARAM%newSnowDenScal)     ! scaling factor for new snow density (K)
 constSnowDen       => mpar_data%var(iLookPARAM%constSnowDen)       ! Constant new snow density (kg m-3)
 newSnowDenAdd      => mpar_data%var(iLookPARAM%newSnowDenAdd)      ! Pahaut 1976, additive factor for new snow density (kg m-3)
 newSnowDenMultTemp => mpar_data%var(iLookPARAM%newSnowDenMultTemp) ! Pahaut 1976, multiplier for new snow density applied to air temperature (kg m-3 K-1)
 newSnowDenMultWind => mpar_data%var(iLookPARAM%newSnowDenMultWind) ! Pahaut 1976, multiplier for new snow density applied to wind speed (kg m-7/2 s-1/2)
 newSnowDenMultAnd  => mpar_data%var(iLookPARAM%newSnowDenMultAnd)  ! Anderson 1976, multiplier for new snow density for Anderson function (K-1)
 newSnowDenBase     => mpar_data%var(iLookPARAM%newSnowDenBase)     ! Anderson 1976, base value that is rasied to the (3/2) power (K)
 ! assign pointers to radiation geometry variables
 im        => time_data%var(iLookTIME%im)                           ! month
 id        => time_data%var(iLookTIME%id)                           ! day
 ih        => time_data%var(iLookTIME%ih)                           ! hour
 imin      => time_data%var(iLookTIME%imin)                         ! minute
 latitude  => attr_data%var(iLookATTR%latitude)                     ! latitude (degrees north
 cosZenith => mvar_data%var(iLookMVAR%scalarCosZenith)%dat(1)       ! average cosine of the zenith angle over time step DT
 ! assign pointers to model forcing data
 SWRadAtm => forc_data%var(iLookFORCE%SWRadAtm)                     ! downward shortwave radiation (W m-2)
 airtemp  => forc_data%var(iLookFORCE%airtemp)                      ! air temperature at 2 meter height (K)
 windspd  => forc_data%var(iLookFORCE%windspd)                      ! wind speed at 10 meter height (m s-1)
 airpres  => forc_data%var(iLookFORCE%airpres)                      ! air pressure at 2 meter height (Pa)
 spechum  => forc_data%var(iLookFORCE%spechum)                      ! specific humidity at 2 meter height (g g-1)
 pptrate  => forc_data%var(iLookFORCE%pptrate)                      ! precipitation rate (kg m-2 s-1)
 ! assign pointers to derived model forcing data
 scalarO2air  => mvar_data%var(iLookMVAR%scalarO2air)%dat(1)        ! atmospheric o2 concentration (Pa)
 scalarCO2air => mvar_data%var(iLookMVAR%scalarCO2air)%dat(1)       ! atmospheric co2 concentration (Pa)
 ! assign pointers to radiation variables
 scalarFractionDirect    => mvar_data%var(iLookMVAR%scalarFractionDirect)%dat(1)    ! fraction of direct radiation (0-1)
 spectralIncomingDirect  => mvar_data%var(iLookMVAR%spectralIncomingDirect)%dat     ! downwelling direct shortwave radiation for each waveband (W m-2)
 spectralIncomingDiffuse => mvar_data%var(iLookMVAR%spectralIncomingDiffuse)%dat    ! downwelling diffuse shortwave radiation for each waveband (W m-2)
 if(size(spectralIncomingDirect) /= 2 .or. size(spectralIncomingDiffuse) /= 2)then
  err=20; message=trim(message)//'expect two spectral classes for radiation'; return
 endif
 ! assign pointers to snow accumulation variables
 VPair          => mvar_data%var(iLookMVAR%scalarVPair)%dat(1)          ! vapor pressure of the air above the vegetation canopy (Pa)
 twetbulb       => mvar_data%var(iLookMVAR%scalarTwetbulb)%dat(1)       ! wet bulb temperature (K)
 rainfall       => mvar_data%var(iLookMVAR%scalarRainfall)%dat(1)       ! computed rainfall rate (kg m-2 s-1)
 snowfall       => mvar_data%var(iLookMVAR%scalarSnowfall)%dat(1)       ! computed snowfall rate (kg m-2 s-1)
 snowfallTemp   => mvar_data%var(iLookMVAR%scalarSnowfallTemp)%dat(1)   ! computed temperature of fresh snow (K)
 newSnowDensity => mvar_data%var(iLookMVAR%scalarNewSnowDensity)%dat(1) ! computed density of new snow (kg m-3)

 ! compute the partial pressure of o2 and co2
 scalarCO2air = co2Factor * airpres  ! atmospheric co2 concentration (Pa)
 scalarO2air  = o2Factor * airpres   ! atmospheric o2 concentration (Pa)

 ! compute the decimal hour at the start of the time step
 dataStep = data_step/secprhour  ! time step (hours)
 ahour    = real(ih,kind(dp)) + real(imin,kind(dp))/minprhour - data_step/secprhour  ! decimal hour (start of the step)

 ! compute the cosine of the solar zenith angle
 call clrsky_rad(im,id,ahour,dataStep,   &  ! intent(in): time variables
                 slope,azimuth,latitude, &  ! intent(in): location variables
                 hri,cosZenith)             ! intent(out): cosine of the solar zenith angle
 !write(*,'(a,1x,4(i2,1x),3(f9.3,1x))') 'im,id,ih,imin,ahour,dataStep,cosZenith = ', &
 
 ! ensure solar radiation is non-negative
 if(SWRadAtm < 0._dp) SWRadAtm = 0._dp
 ! compute the fraction of direct radiation using the parameterization of Nijssen and Lettenmaier (1999)
 if(cosZenith > 0._dp)then
  scalarFractionDirect = Frad_direct*cosZenith/(cosZenith + directScale)
 else
  scalarFractionDirect = 0._dp
 endif
 ! compute direct shortwave radiation, in the visible and near-infra-red part of the spectrum
 spectralIncomingDirect(1) = SWRadAtm*scalarFractionDirect*Frad_vis                         ! (direct vis)
 spectralIncomingDirect(2) = SWRadAtm*scalarFractionDirect*(1._dp - Frad_vis)               ! (direct nir)
 ! compute diffuse shortwave radiation, in the visible and near-infra-red part of the spectrum
 spectralIncomingDiffuse(1) = SWRadAtm*(1._dp - scalarFractionDirect)*Frad_vis              ! (diffuse vis)
 spectralIncomingDiffuse(2) = SWRadAtm*(1._dp - scalarFractionDirect)*(1._dp - Frad_vis)    ! (diffuse nir)

 ! ensure wind speed is above a prescribed minimum value
 if(windspd < minwind) windspd=minwind

 ! compute relative humidity (-)
 relhum   = SPHM2RELHM(spechum, airpres, airtemp)
 ! if relative humidity exceeds saturation, then set relative and specific humidity to saturation
 if(relhum > 1._dp)then
  relhum  = 1._dp
  spechum = RELHM2SPHM(relhum, airpres, airtemp)
 endif

 ! compute vapor pressure of the air above the vegetation canopy (Pa)
 VPair = vapPress(spechum,airpres)
 !print*, 'VPair = ', VPair

 ! compute wet bulb temperature (K)
 twetbulb = WETBULBTMP(airtemp, relhum, airpres)

 ! compute the maximum temperature of snow when the snow is predominantely frozen (K)
 maxFrozenSnowTemp = templiquid(unfrozenLiq,fc_param)

 ! compute fraction of rain and temperature of fresh snow
 Tmin = twetbulb - tempRangeTimestep/2._dp
 Tmax = twetbulb + tempRangeTimestep/2._dp
 if(Tmax < tempCritRain)then
  fracrain     = 0._dp
  snowfallTemp = twetbulb
 elseif(Tmin > tempCritRain)then
  fracrain     = 1._dp
  snowfallTemp = maxFrozenSnowTemp
 else
  fracrain     = (Tmax - tempCritRain)/(Tmax - Tmin)
  snowfallTemp = 0.5_dp*(Tmin + maxFrozenSnowTemp)
 endif
 !write(*,'(a,1x,10(f20.10,1x))') 'Tmin, twetbulb, tempRangeTimestep, tempCritRain = ', &
 !                                 Tmin, twetbulb, tempRangeTimestep, tempCritRain

 ! ensure that snowfall temperature creates predominantely solid precipitation
 snowfallTemp      = min(maxFrozenSnowTemp,snowfallTemp) ! snowfall temperature

 ! ensure precipitation rate can be resolved by the data model
 if(pptrate<eps)then
  ! set rainfall and snowfall to zero
  rainfall     = 0._dp
  snowfall     = 0._dp
 else
  ! compute rainfall and snowfall
  rainfall = fracrain*pptrate
  snowfall = (1._dp - fracrain)*pptrate*frozenPrecipMultip
 endif

 !print*, 'tempCritRain, tempRangeTimestep, pptrate, airtemp, rainfall, snowfall, twetbulb, relhum, snowfallTemp = '
 !print*, tempCritRain, tempRangeTimestep, pptrate, airtemp, rainfall, snowfall, twetbulb, relhum, snowfallTemp

 ! compute density of new snow
 if(snowfall > tiny(fracrain))then
  ! Determine which method to use 
  select case(model_decisions(iLookDECISIONS%snowDenNew)%iDecision)
   ! Hedstrom and Pomeroy 1998
   case(hedAndPom) 
    newSnowDensity = min(pomNewSnowDenMax,newSnowDenMin + newSnowDenMult*exp((airtemp-Tfreeze)/newSnowDenScal))  ! new snow density (kg m-3)
   ! Pahaut 1976 (Boone et al. 2002)
   case(pahaut_76)
    newSnowDensity = max(newSnowDenMin,newSnowDenAdd + (newSnowDenMultTemp * (airtemp-Tfreeze))+(newSnowDenMultWind*((windspd)**pahautDenWindScal))); ! new snow density (kg m-3)
   ! Anderson 1976 
   case(anderson) 
    if(airtemp>(Tfreeze+andersonWarmDenLimit))then
     newSnowDensity = newSnowDenMin + newSnowDenMultAnd*(newSnowDenBase)**(andersonDenScal) ! new snow density (kg m-3)
    elseif(airtemp<=(Tfreeze-andersonColdDenLimit))then
     newSnowDensity = newSnowDenMin ! new snow density (kg m-3)
    else
     newSnowDensity = newSnowDenMin + newSnowDenMultAnd*(airtemp-Tfreeze+newSnowDenBase)**(andersonDenScal) ! new snow density (kg m-3)
    endif
   ! Constant new snow density
   case(constDens) 
    newSnowDensity = constSnowDen; ! new snow density (kg m-3)
   case default; message=trim(message)//'unable to identify option for new snow density'; err=20; return
  end select ! identifying option for new snow density
 else
  newSnowDensity = valueMissing
  rainfall = rainfall + snowfall ! in most cases snowfall will be zero here
  snowfall = 0._dp
 endif

 end subroutine derivforce


end module derivforce_module
