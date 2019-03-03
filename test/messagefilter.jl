
function createBroker(core_type="zmq", number_of_federates=1)

    initstring = "$number_of_federates --name=mainbroker"

    broker = h.helicsCreateBroker(core_type, "", initstring)

    isconnected = h.helicsBrokerIsConnected(broker)

    @test isconnected == true

    return broker

end

function createFederate(broker, core_type="zmq", count=1, deltat=1.0, name_prefix="fed")

    # Create Federate Info object that describes the federate properties #
    fedinfo = h.helicsCreateFederateInfo()

    # Set Federate name #
    h.helicsFederateInfoSetCoreName(fedinfo, name_prefix)

    # Set core type from string #
    h.helicsFederateInfoSetCoreTypeFromString(fedinfo, "zmq")

    # Federate init string #
    fedinitstring = "--broker=mainbroker --federates=$count"
    h.helicsFederateInfoSetCoreInitString(fedinfo, fedinitstring)

    # Set the message interval (timedelta) for federate. Note th#
    # HELICS minimum message time interval is 1 ns and by default
    # it uses a time delta of 1 second. What is provided to the
    # setTimedelta routine is a multiplier for the default timedelta.

    # Set one second message interval #
    h.helicsFederateInfoSetTimeProperty(fedinfo, h.HELICS_PROPERTY_TIME_DELTA, deltat)

    h.helicsFederateInfoSetIntegerProperty(fedinfo, h.HELICS_PROPERTY_INT_LOG_LEVEL, -1)

    mFed = h.helicsCreateMessageFederate(name_prefix, fedinfo)

    return mFed, fedinfo
end

function destroyFederate(fed, fedinfo)
    h.helicsFederateFinalize(fed)
    state = h.helicsFederateGetState(fed)
    @test state == 3 # TODO: should this be 3?

    h.helicsFederateInfoFree(fedinfo)
    h.helicsFederateFree(fed)
end


function destroyBroker(broker)
    h.helicsBrokerDisconnect(broker)
    h.helicsCloseLibrary()
end

@testset "Broker" begin
    broker = createBroker("zmq", 1)

    initstring = "--broker="
    identifier = h.helicsBrokerGetIdentifier(broker)
    initstring = initstring * identifier
    initstring = initstring * " --broker_address "
    address = h.helicsBrokerGetAddress(broker)
    initstring = initstring * address
    @test initstring == "--broker=mainbroker --broker_address tcp://127.0.0.1:23404"
    destroyBroker(broker)

end

@testset "MessageFilter Registration" begin

    broker = createBroker("zmq", 1)

    fFed, ffedinfo = createFederate(broker, "zmq", 1, 1, "filter")
    mFed, mfedinfo = createFederate(broker, "zmq", 1, 1, "message")

    h.helicsFederateRegisterGlobalEndpoint(mFed, "port1", "")
    h.helicsFederateRegisterGlobalEndpoint(mFed, "port2", "")

    f1 = h.helicsFederateRegisterFilter(fFed, h.HELICS_FILTER_TYPE_CUSTOM, "filter1")
    f2 = h.helicsFederateRegisterFilter(fFed, h.HELICS_FILTER_TYPE_CUSTOM, "filter2")
    h.helicsFederateRegisterEndpoint(fFed, "fout", "")
    h.helicsFederateRegisterFilter(fFed, h.HELICS_FILTER_TYPE_CUSTOM,  "filter0/fout")
    h.helicsFederateEnterExecutingModeAsync(fFed)
    h.helicsFederateEnterExecutingMode(mFed)
    h.helicsFederateEnterExecutingModeComplete(fFed)

    filter_name = h.helicsFilterGetName(f1)
    @test filter_name == "filter/filter1"

    filter_name = h.helicsFilterGetName(f2)
    @test filter_name == "filter/filter2"

    # filter_target = h.helicsFilterGetTarget(f2)
    # @test filter_target == "port2"

    h.helicsFederateFinalize(mFed)
    h.helicsFederateFinalize(fFed)

    destroyFederate(fFed, ffedinfo)
    destroyFederate(mFed, mfedinfo)
    sleep(1.0)

    destroyBroker(broker)
end


@testset "MessageFilter Function" begin
    broker = createBroker("zmq", 1)

    fFed, ffedinfo = createFederate(broker, "zmq", 1, 1, "filter")
    mFed, mfedinfo = createFederate(broker, "zmq", 1, 1, "message")

    p1 = h.helicsFederateRegisterGlobalEndpoint(mFed, "port1", "")
    p2 = h.helicsFederateRegisterGlobalEndpoint(mFed, "port2", "random")

    f1 = h.helicsFederateRegisterGlobalFilter(fFed, h.HELICS_FILTER_TYPE_CUSTOM, "filter1")
    h.helicsFilterAddSourceTarget(f1, "port1")
    f2 = h.helicsFederateRegisterGlobalFilter(fFed, h.HELICS_FILTER_TYPE_DELAY, "filter2")
    h.helicsFilterAddSourceTarget(f2, "port1")
    h.helicsFederateRegisterEndpoint(fFed,"fout","")
    f3 = h.helicsFederateRegisterFilter(fFed, h.HELICS_FILTER_TYPE_RANDOM_DELAY, "filter3")
    h.helicsFilterAddSourceTarget(f3,"filter/fout")

    h.helicsFilterSet(f2, "delay", 2.5)
    h.helicsFederateEnterExecutingModeAsync(fFed)
    h.helicsFederateEnterExecutingMode(mFed)
    h.helicsFederateEnterExecutingModeComplete(fFed)
    state = h.helicsFederateGetState(fFed)
    @test state == 2
    data = "hello world"

    filt_key = h.helicsFilterGetName(f1)
    @test filt_key == "filter1"

    filt_key = h.helicsFilterGetName(f2)
    @test filt_key == "filter2"

    h.helicsEndpointSendMessageRaw(p1, "port2", data)
    h.helicsFederateRequestTimeAsync(mFed, 1.0)
    grantedtime = h.helicsFederateRequestTime(fFed, 1.0)
    @test grantedtime == 1.0
    grantedtime = h.helicsFederateRequestTimeComplete(mFed)
    @test grantedtime == 1.0
    res = h.helicsFederateHasMessage(mFed)
    @test res == 0
    res = h.helicsEndpointHasMessage(p2)
    @test res == 0
    #grantedtime = h.helicsFederateRequestTime(fFed, 3.0)
    #@test res==h.helics_true

    h.helicsFederateFinalize(mFed)
    h.helicsFederateFinalize(fFed)
    #f2 = h.helicsFederateRegisterDestinationFilter(fFed, h.helics_custom_filter, "filter2", "port2")
    #ep1 = h.helicsFederateRegisterEndpoint(fFed, "fout", "")
    #f3 = h.helicsFederateRegisterSourceFilter(fFed, h.helics_custom_filter, "", "filter0/fout")

    destroyFederate(fFed, ffedinfo)
    destroyFederate(mFed, mfedinfo)
    sleep(1.0)
    destroyBroker(broker)

end
