#if os(Linux)
import Adwaita
import CAdw
import Foundation

/// Pass ImageSource.card(..., overframe: game.showsOverframe(cid)); never infer unlocks from URLs.
@MainActor struct LinuxPicture: AdwaitaWidget {
    let request: ImageRequest?
    var size: LinuxImageLoader.Size = .grid
    var loader: LinuxImageLoader = .shared
    func container<T>(data: WidgetData, type: T.Type) -> ViewStorage where T: ViewRenderData {
        makeStorage()
    }
    /// Native constructor shared by the Adwaita adapter and display-backed regression probe.
    func makeStorage() -> ViewStorage {
        let picture = gtk_picture_new()!
        gtk_picture_set_can_shrink(OpaquePointer(picture), 1)
        let storage = ViewStorage(OpaquePointer(picture))
        let binding = LinuxPictureBinding(picture: OpaquePointer(picture), loader: loader)
        storage.fields["linux-picture-binding"] = binding
        // GObject's weak notification runs on GTK destruction; it never owns a widget reference.
        g_object_weak_ref(UnsafeMutableRawPointer(picture).assumingMemoryBound(to: GObject.self), { context, _ in
            guard let context else { return }
            let binding = Unmanaged<LinuxPictureBinding>.fromOpaque(context).takeRetainedValue()
            MainActor.assumeIsolated { binding.destroy() }
        }, Unmanaged.passRetained(binding).toOpaque())
        updatePicture(storage)
        return storage
    }
    func update<T>(_ storage: ViewStorage, data: WidgetData, updateProperties: Bool, type: T.Type) where T: ViewRenderData {
        guard updateProperties else { return }
        updatePicture(storage)
    }
    func updatePicture(_ storage: ViewStorage) {
        guard let binding = storage.fields["linux-picture-binding"] as? LinuxPictureBinding else { return }
        binding.update(request: request, size: size)
    }
}

@MainActor private final class LinuxPictureBinding {
    private var picture: OpaquePointer?
    private let loader: LinuxImageLoader
    private var identity: LinuxTextureCache.Key?
    private var token: UUID?
    private var generation: UInt64 = 0
    init(picture: OpaquePointer, loader: LinuxImageLoader) { self.picture = picture; self.loader = loader }
    func update(request: ImageRequest?, size: LinuxImageLoader.Size) {
        let identity = LinuxTextureCache.Key(source: request?.key ?? "bundled-card-back", pixels: size.rawValue)
        guard picture != nil, self.identity != identity else { return }
        self.identity = identity; generation &+= 1
        if let token { loader.unsubscribe(token) }; token = nil
        display(loader.placeholder(size: size))
        guard let request else { return }
        let generation = generation
        token = loader.subscribe(request, size: size) { [weak self] texture in
            guard let self, self.generation == generation, self.picture != nil else { return }
            if let texture { self.display(texture) }
        }
    }
    private func display(_ texture: LinuxTextureCache.Texture?) {
        guard let picture else { return }
        gtk_picture_set_paintable(picture, texture?.pointer)
    }
    func destroy() {
        picture = nil; generation &+= 1
        if let token { loader.unsubscribe(token) }; token = nil
    }
}
#endif
