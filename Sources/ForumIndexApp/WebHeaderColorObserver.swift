import WebKit

/// Kept separate from the preloader to avoid a web-view/message-handler retain cycle.
@MainActor
final class WebHeaderColorObserver: NSObject, WKScriptMessageHandler {
    var onColor: ((WKScriptMessage) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        onColor?(message)
    }

    static let script = #"""
    (() => {
        window.forumIndexHeaderObserver?.disconnect();
        let scheduled = false;
        let previous = "";
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = 1;
        const context = canvas.getContext("2d", { willReadFrequently: true });
        function sample() {
            scheduled = false;
            const header = Array.from(document.querySelectorAll(".d-header, header, [role='banner'], #header"))
                .find(element => {
                    const rect = element.getBoundingClientRect();
                    const style = getComputedStyle(element);
                    return rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none";
                });
            if (!header || !context) return;
            const ancestors = [];
            for (let element = header; element; element = element.parentElement) ancestors.push(element);
            context.clearRect(0, 0, 1, 1);
            // Composite translucent header backgrounds over their actual ancestor colors.
            for (const element of ancestors.reverse()) {
                context.fillStyle = getComputedStyle(element).backgroundColor;
                context.fillRect(0, 0, 1, 1);
            }
            const rgba = Array.from(context.getImageData(0, 0, 1, 1).data);
            if (rgba[3] !== 255) return;
            const value = rgba.join(",");
            if (value === previous) return;
            previous = value;
            window.webkit.messageHandlers.forumIndexHeaderColor.postMessage({ token, rgba });
        }
        function schedule() {
            if (scheduled) return;
            scheduled = true;
            requestAnimationFrame(sample);
        }
        const observer = new MutationObserver(schedule);
        observer.observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
        window.addEventListener("resize", schedule);
        document.addEventListener("load", schedule, true);
        const theme = matchMedia("(prefers-color-scheme: dark)");
        theme.addEventListener("change", schedule);
        window.forumIndexHeaderObserver = {
            disconnect() {
                observer.disconnect();
                window.removeEventListener("resize", schedule);
                document.removeEventListener("load", schedule, true);
                theme.removeEventListener("change", schedule);
            }
        };
        schedule();
    })();
    """#
}
