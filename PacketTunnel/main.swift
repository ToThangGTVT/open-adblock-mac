import Foundation
import NetworkExtension

// A system extension is its own process: hand control to the Network Extension framework,
// which instantiates PacketTunnelProvider (NEProviderClasses in Config/PacketTunnel-Info.plist).
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
