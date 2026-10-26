import Foundation

public struct StarterPreset: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var defaultProfessions: Set<ReviewAIProfession>
    public var rules: [Rule]
}

public enum StarterPresets {
    public static let catalogVersion = 1

    public static let packs: [StarterPreset] = [
        everydayPersonal, socialMedia,
        softwareDevelopment, design, productManagement, data, marketing, sales, businessOwner, writing,
        education, research, healthcare, legal, finance, engineering, skilledTrades, operations, student
    ]

    public static func defaultPresetIDs(for profession: ReviewAIProfession) -> Set<String> {
        Set(packs.filter { $0.defaultProfessions.contains(profession) }.map(\.id))
    }

    public static func presetIDs(_ selected: Set<String>, switchingFrom old: ReviewAIProfession, to new: ReviewAIProfession) -> Set<String> {
        let oldDefaults = defaultPresetIDs(for: old)
        let newDefaults = defaultPresetIDs(for: new)
        return selected.subtracting(oldDefaults.subtracting(newDefaults)).union(newDefaults.subtracting(oldDefaults))
    }

    private static let everyone = Set(ReviewAIProfession.allCases)

    static let everydayPersonal = pack(
        "everyday-personal", "Everyday personal",
        "Streaming, music, shopping, food delivery, games, dating and entertainment sites are Personal.",
        kind: .personal, idPrefix: "41000000", defaultFor: everyone, [
            site(1, "Netflix", "netflix.com"),
            site(2, "Disney+", "disneyplus.com"),
            site(3, "Hulu", "hulu.com"),
            site(4, "Max", "max.com"),
            site(5, "HBO Max", "hbomax.com"),
            site(6, "Prime Video", "primevideo.com"),
            site(7, "Peacock", "peacocktv.com"),
            site(8, "Paramount+", "paramountplus.com"),
            site(9, "Crunchyroll", "crunchyroll.com"),
            site(10, "Twitch", "twitch.tv"),
            site(11, "Kick", "kick.com"),
            site(12, "Tubi", "tubitv.com"),
            site(13, "Pluto TV", "pluto.tv"),
            site(14, "MUBI", "mubi.com"),
            site(15, "Plex", "plex.tv"),
            site(16, "Sling TV", "sling.com"),
            site(17, "Fubo", "fubo.tv"),
            host(18, "Apple TV on the web", "tv.apple.com"),
            app(19, "Apple TV", "com.apple.TV"),
            app(20, "Spotify", "com.spotify.client"),
            host(21, "Spotify on the web", "open.spotify.com"),
            app(22, "Music", "com.apple.Music"),
            host(23, "Apple Music on the web", "music.apple.com"),
            host(24, "YouTube Music", "music.youtube.com"),
            site(25, "SoundCloud", "soundcloud.com"),
            site(26, "Pandora", "pandora.com"),
            site(27, "Deezer", "deezer.com"),
            site(28, "Tidal", "tidal.com"),
            host(29, "Amazon", "www.amazon.com"),
            host(30, "Amazon UK", "www.amazon.co.uk"),
            host(31, "Amazon Germany", "www.amazon.de"),
            host(32, "Amazon Canada", "www.amazon.ca"),
            host(33, "Amazon Australia", "www.amazon.com.au"),
            host(34, "Amazon India", "www.amazon.in"),
            site(35, "eBay", "ebay.com"),
            site(36, "eBay UK", "ebay.co.uk"),
            site(37, "eBay Germany", "ebay.de"),
            site(38, "Walmart", "walmart.com"),
            site(39, "Target", "target.com"),
            site(40, "Best Buy", "bestbuy.com"),
            site(41, "IKEA", "ikea.com"),
            site(42, "Wayfair", "wayfair.com"),
            site(43, "Costco", "costco.com"),
            site(44, "AliExpress", "aliexpress.com"),
            site(45, "Temu", "temu.com"),
            site(46, "Shein", "shein.com"),
            site(47, "ASOS", "asos.com"),
            site(48, "Zara", "zara.com"),
            site(49, "H&M", "hm.com"),
            site(50, "Nike", "nike.com"),
            site(51, "Sephora", "sephora.com"),
            site(52, "Ulta Beauty", "ulta.com"),
            site(53, "Nordstrom", "nordstrom.com"),
            site(54, "Macy’s", "macys.com"),
            site(55, "Chewy", "chewy.com"),
            site(56, "Instacart", "instacart.com"),
            site(57, "DoorDash", "doordash.com"),
            site(58, "Uber Eats", "ubereats.com"),
            site(59, "Grubhub", "grubhub.com"),
            site(60, "Deliveroo", "deliveroo.co.uk"),
            app(61, "Steam", "com.valvesoftware.steam"),
            site(62, "Steam Store", "steampowered.com"),
            site(63, "Steam Community", "steamcommunity.com"),
            app(64, "Epic Games Launcher", "com.epicgames.EpicGamesLauncher"),
            host(65, "Epic Games Store", "store.epicgames.com"),
            site(66, "GOG", "gog.com"),
            app(67, "Roblox", "com.roblox.RobloxPlayer"),
            site(68, "Roblox on the web", "roblox.com"),
            app(69, "Minecraft Launcher", "com.mojang.minecraftlauncher"),
            app(70, "Chess", "com.apple.Chess"),
            site(71, "Chess.com", "chess.com"),
            site(72, "Lichess", "lichess.org"),
            site(73, "Poki", "poki.com"),
            site(74, "CrazyGames", "crazygames.com"),
            site(75, "Xbox", "xbox.com"),
            site(76, "PlayStation", "playstation.com"),
            site(77, "Nintendo", "nintendo.com"),
            site(78, "Tinder", "tinder.com"),
            site(79, "Bumble", "bumble.com"),
            site(80, "Hinge", "hinge.co"),
            site(81, "OkCupid", "okcupid.com"),
            site(82, "Match", "match.com"),
            site(83, "Plenty of Fish", "pof.com"),
            site(84, "eharmony", "eharmony.com"),
            site(85, "Coffee Meets Bagel", "coffeemeetsbagel.com"),
            site(86, "Feeld", "feeld.co"),
            site(87, "Grindr", "grindr.com"),
            site(88, "ESPN", "espn.com"),
            site(89, "Bleacher Report", "bleacherreport.com"),
            site(90, "CBS Sports", "cbssports.com"),
            site(91, "Sky Sports", "skysports.com"),
            host(92, "Yahoo Sports", "sports.yahoo.com"),
            site(93, "Sleeper", "sleeper.com"),
            site(94, "DraftKings", "draftkings.com"),
            site(95, "FanDuel", "fanduel.com"),
            site(96, "TMZ", "tmz.com"),
            site(97, "People", "people.com"),
            site(98, "E! Online", "eonline.com"),
            site(99, "BuzzFeed", "buzzfeed.com"),
            site(100, "9GAG", "9gag.com"),
            site(101, "IMDb", "imdb.com"),
            site(102, "Rotten Tomatoes", "rottentomatoes.com"),
            site(103, "Letterboxd", "letterboxd.com"),
            site(104, "Fandom", "fandom.com"),
            site(105, "Allrecipes", "allrecipes.com")
        ])

    static let socialMedia = pack(
        "social-media", "Social media",
        "Facebook, Instagram, TikTok, X and similar feeds are Personal. Off by default for marketing and business owners.",
        kind: .personal, idPrefix: "42000000", defaultFor: everyone.subtracting([.marketing, .businessOwner]), [
            host(1, "Facebook", "www.facebook.com"),
            host(2, "Facebook", "facebook.com"),
            host(3, "Facebook mobile", "m.facebook.com"),
            site(4, "Instagram", "instagram.com"),
            host(5, "TikTok", "www.tiktok.com"),
            host(6, "Snapchat", "web.snapchat.com"),
            host(7, "X", "x.com"),
            host(8, "Twitter", "twitter.com"),
            site(9, "Threads", "threads.net"),
            site(10, "Threads", "threads.com"),
            site(11, "Bluesky", "bsky.app"),
            site(12, "Tumblr", "tumblr.com"),
            site(13, "Mastodon", "mastodon.social")
        ])

    static let softwareDevelopment = pack(
        "software-development", "Software development",
        "Editors, terminals, code hosts, package registries and cloud consoles are Work.",
        kind: .work, idPrefix: "40000000", defaultFor: [.softwareDeveloper], [
            app(1, "Xcode", "com.apple.dt.Xcode"),
            app(2, "Visual Studio Code", "com.microsoft.VSCode"),
            app(3, "Cursor", "com.todesktop.230313mzl4w4u92"),
            app(4, "Android Studio", "com.google.android.studio"),
            app(5, "IntelliJ IDEA", "com.jetbrains.intellij"),
            host(6, "Local development", "localhost"),
            app(7, "PyCharm", "com.jetbrains.pycharm"),
            app(8, "PyCharm CE", "com.jetbrains.pycharm.ce"),
            app(9, "WebStorm", "com.jetbrains.WebStorm"),
            app(10, "GoLand", "com.jetbrains.goland"),
            app(11, "CLion", "com.jetbrains.CLion"),
            app(12, "RubyMine", "com.jetbrains.rubymine"),
            app(13, "PhpStorm", "com.jetbrains.PhpStorm"),
            app(14, "Rider", "com.jetbrains.rider"),
            app(15, "RustRover", "com.jetbrains.rustrover"),
            app(16, "IntelliJ IDEA CE", "com.jetbrains.intellij.ce"),
            app(17, "DataGrip", "com.jetbrains.datagrip"),
            app(18, "Sublime Text", "com.sublimetext.4"),
            app(19, "Zed", "dev.zed.Zed"),
            app(20, "Nova", "com.panic.Nova"),
            app(21, "BBEdit", "com.barebones.bbedit"),
            app(22, "Windsurf", "com.exafunction.windsurf"),
            app(23, "Visual Studio Code Insiders", "com.microsoft.VSCodeInsiders"),
            app(24, "MacVim", "org.vim.MacVim"),
            app(25, "Terminal", "com.apple.Terminal"),
            app(26, "iTerm", "com.googlecode.iterm2"),
            app(27, "Warp", "dev.warp.Warp-Stable"),
            app(28, "Ghostty", "com.mitchellh.ghostty"),
            app(29, "Docker Desktop", "com.docker.docker"),
            app(30, "Postman", "com.postmanlabs.mac"),
            app(31, "Insomnia", "com.insomnia.app"),
            app(32, "TablePlus", "com.tinyapp.TablePlus"),
            app(33, "Sequel Ace", "com.sequel-ace.sequel-ace"),
            app(34, "GitHub Desktop", "com.github.GitHubClient"),
            app(35, "Tower", "com.fournova.Tower3"),
            app(36, "Fork", "com.DanPristupov.Fork"),
            app(37, "Sourcetree", "com.torusknot.SourceTreeNotMac"),
            app(38, "Simulator", "com.apple.iphonesimulator"),
            app(39, "Instruments", "com.apple.dt.Instruments"),
            app(40, "Proxyman", "com.proxyman.NSProxy"),
            app(41, "Charles", "com.xk72.Charles"),
            app(42, "Wireshark", "org.wireshark.Wireshark"),
            host(43, "Local development", "127.0.0.1"),
            site(44, "GitHub", "github.com"),
            site(45, "GitLab", "gitlab.com"),
            site(46, "Bitbucket", "bitbucket.org"),
            site(47, "Stack Overflow", "stackoverflow.com"),
            site(48, "Server Fault", "serverfault.com"),
            host(49, "MDN Web Docs", "developer.mozilla.org"),
            host(50, "Apple Developer", "developer.apple.com"),
            host(51, "App Store Connect", "appstoreconnect.apple.com"),
            site(52, "npm", "npmjs.com"),
            site(53, "PyPI", "pypi.org"),
            site(54, "crates.io", "crates.io"),
            host(55, "Go Packages", "pkg.go.dev"),
            site(56, "Docs.rs", "docs.rs"),
            site(57, "Swift Package Index", "swiftpackageindex.com"),
            site(58, "Vercel", "vercel.com"),
            site(59, "Netlify", "netlify.com"),
            site(60, "Heroku", "heroku.com"),
            site(61, "Fly.io", "fly.io"),
            site(62, "Railway", "railway.com"),
            host(63, "Render", "dashboard.render.com"),
            host(64, "DigitalOcean", "cloud.digitalocean.com"),
            site(65, "AWS Console", "console.aws.amazon.com"),
            host(66, "Google Cloud Console", "console.cloud.google.com"),
            host(67, "Firebase Console", "console.firebase.google.com"),
            host(68, "Azure Portal", "portal.azure.com"),
            host(69, "Cloudflare Dashboard", "dash.cloudflare.com"),
            site(70, "Supabase", "supabase.com"),
            host(71, "Docker Hub", "hub.docker.com"),
            site(72, "Sentry", "sentry.io"),
            site(73, "Datadog", "datadoghq.com"),
            site(74, "CircleCI", "circleci.com"),
            site(75, "Buildkite", "buildkite.com"),
            site(76, "Expo", "expo.dev"),
            site(77, "Linear", "linear.app"),
            app(78, "Linear app", "com.linear"),
            site(79, "Jira and Confluence", "atlassian.net"),
            site(80, "CodeSandbox", "codesandbox.io"),
            site(81, "CodePen", "codepen.io"),
            site(82, "Replit", "replit.com"),
            site(83, "regex101", "regex101.com")
        ])

    static let design = pack(
        "design", "Design",
        "Design, illustration, photo and prototyping tools plus design inspiration sites are Work.",
        kind: .work, idPrefix: "43000000", defaultFor: [.designer], [
            app(1, "Figma", "com.figma.Desktop"),
            site(2, "Figma on the web", "figma.com"),
            app(3, "Sketch", "com.bohemiancoding.sketch3"),
            app(4, "Photoshop", "com.adobe.Photoshop"),
            app(5, "Illustrator", "com.adobe.illustrator"),
            app(6, "InDesign", "com.adobe.InDesign"),
            app(7, "After Effects", "com.adobe.AfterEffects"),
            app(8, "Adobe XD", "com.adobe.xd"),
            app(9, "Lightroom Classic", "com.adobe.LightroomClassicCC7"),
            app(10, "Affinity Designer 2", "com.seriflabs.affinitydesigner2"),
            app(11, "Affinity Photo 2", "com.seriflabs.affinityphoto2"),
            app(12, "Affinity Publisher 2", "com.seriflabs.affinitypublisher2"),
            app(13, "Pixelmator Pro", "com.pixelmatorteam.pixelmator.x"),
            app(14, "Blender", "org.blenderfoundation.blender"),
            app(15, "Zeplin", "io.zeplin.osx"),
            app(16, "Glyphs 3", "com.GeorgSeifert.Glyphs3"),
            site(17, "Dribbble", "dribbble.com"),
            site(18, "Behance", "behance.net"),
            site(19, "Framer", "framer.com"),
            site(20, "Canva", "canva.com"),
            site(21, "Webflow", "webflow.com"),
            site(22, "Zeplin on the web", "zeplin.io"),
            site(23, "Spline", "spline.design"),
            site(24, "Penpot", "penpot.app"),
            site(25, "LottieFiles", "lottiefiles.com"),
            site(26, "Mobbin", "mobbin.com"),
            site(27, "Awwwards", "awwwards.com"),
            site(28, "Coolors", "coolors.co"),
            host(29, "Google Fonts", "fonts.google.com"),
            host(30, "Adobe Fonts", "fonts.adobe.com"),
            host(31, "Adobe Color", "color.adobe.com"),
            host(32, "Adobe Stock", "stock.adobe.com"),
            site(33, "Unsplash", "unsplash.com"),
            site(34, "Relume", "relume.io"),
            site(35, "UXPin", "uxpin.com"),
            site(36, "ProtoPie", "protopie.io"),
            site(37, "Maze", "maze.co"),
            site(38, "Miro", "miro.com")
        ])

    static let productManagement = pack(
        "product-management", "Product and project management",
        "Roadmaps, issue trackers, product analytics and research tools are Work.",
        kind: .work, idPrefix: "44000000", defaultFor: [.productManager], [
            site(1, "Linear", "linear.app"),
            app(2, "Linear app", "com.linear"),
            site(3, "Jira and Confluence", "atlassian.net"),
            site(4, "Productboard", "productboard.com"),
            site(5, "Aha!", "aha.io"),
            site(6, "Asana", "asana.com"),
            site(7, "monday.com", "monday.com"),
            site(8, "Smartsheet", "smartsheet.com"),
            site(9, "Miro", "miro.com"),
            site(10, "Figma", "figma.com"),
            app(11, "Figma app", "com.figma.Desktop"),
            site(12, "Amplitude", "amplitude.com"),
            site(13, "Mixpanel", "mixpanel.com"),
            site(14, "PostHog", "posthog.com"),
            site(15, "Pendo", "pendo.io"),
            site(16, "FullStory", "fullstory.com"),
            site(17, "Hotjar", "hotjar.com"),
            site(18, "Dovetail", "dovetail.com"),
            site(19, "Lucid", "lucid.app"),
            site(20, "ProductPlan", "productplan.com"),
            site(21, "Canny", "canny.io"),
            site(22, "LaunchDarkly", "launchdarkly.com"),
            site(23, "Statsig", "statsig.com"),
            site(24, "Maze", "maze.co"),
            site(25, "User Interviews", "userinterviews.com")
        ])

    static let data = pack(
        "data", "Data analysis",
        "Notebooks, warehouses, BI dashboards, SQL clients and spreadsheets are Work.",
        kind: .work, idPrefix: "45000000", defaultFor: [.dataAnalyst], [
            app(1, "Tableau Desktop", "com.tableausoftware.tableaudesktop"),
            app(2, "DataGrip", "com.jetbrains.datagrip"),
            app(3, "DBeaver", "org.jkiss.dbeaver.core.product"),
            app(4, "TablePlus", "com.tinyapp.TablePlus"),
            app(5, "RStudio", "com.rstudio.desktop"),
            app(6, "Excel", "com.microsoft.Excel"),
            site(7, "Kaggle", "kaggle.com"),
            host(8, "Google Colab", "colab.research.google.com"),
            site(9, "Databricks", "cloud.databricks.com"),
            site(10, "Azure Databricks", "azuredatabricks.net"),
            host(11, "Snowflake", "app.snowflake.com"),
            site(12, "Snowflake accounts", "snowflakecomputing.com"),
            host(13, "BigQuery and Google Cloud", "console.cloud.google.com"),
            host(14, "Looker Studio", "lookerstudio.google.com"),
            site(15, "Looker", "looker.com"),
            site(16, "Tableau", "tableau.com"),
            host(17, "Power BI", "app.powerbi.com"),
            site(18, "Mode", "mode.com"),
            site(19, "Hex", "hex.tech"),
            site(20, "Observable", "observablehq.com"),
            site(21, "Deepnote", "deepnote.com"),
            site(22, "Hugging Face", "huggingface.co"),
            site(23, "dbt Cloud", "getdbt.com"),
            site(24, "Sigma", "sigmacomputing.com"),
            site(25, "Fivetran", "fivetran.com")
        ])

    static let marketing = pack(
        "marketing", "Marketing",
        "Ad managers, SEO, email, social scheduling and analytics tools are Work. Social feeds stay unresolved.",
        kind: .work, idPrefix: "46000000", defaultFor: [.marketing], [
            site(1, "HubSpot", "hubspot.com"),
            site(2, "Mailchimp", "mailchimp.com"),
            site(3, "Semrush", "semrush.com"),
            site(4, "Ahrefs", "ahrefs.com"),
            site(5, "Moz", "moz.com"),
            host(6, "Google Ads", "ads.google.com"),
            host(7, "Google Analytics", "analytics.google.com"),
            host(8, "Google Search Console", "search.google.com"),
            host(9, "Google Tag Manager", "tagmanager.google.com"),
            host(10, "Google Trends", "trends.google.com"),
            host(11, "Meta Business Suite", "business.facebook.com"),
            host(12, "Meta Ads Manager", "adsmanager.facebook.com"),
            host(13, "TikTok Ads", "ads.tiktok.com"),
            host(14, "X Ads", "ads.x.com"),
            host(15, "Snapchat Ads", "ads.snapchat.com"),
            site(16, "Hootsuite", "hootsuite.com"),
            site(17, "Buffer", "buffer.com"),
            site(18, "Sprout Social", "sproutsocial.com"),
            site(19, "Later", "later.com"),
            site(20, "Metricool", "metricool.com"),
            site(21, "Agorapulse", "agorapulse.com"),
            site(22, "Klaviyo", "klaviyo.com"),
            site(23, "Marketo", "marketo.com"),
            site(24, "Brevo", "brevo.com"),
            site(25, "Constant Contact", "constantcontact.com"),
            site(26, "ActiveCampaign", "activecampaign.com"),
            site(27, "Similarweb", "similarweb.com"),
            site(28, "BuzzSumo", "buzzsumo.com"),
            site(29, "Canva", "canva.com"),
            site(30, "Unbounce", "unbounce.com"),
            site(31, "Optimizely", "optimizely.com"),
            site(32, "Meltwater", "meltwater.com"),
            site(33, "Brandwatch", "brandwatch.com"),
            site(34, "AnswerThePublic", "answerthepublic.com")
        ])

    static let sales = pack(
        "sales", "Sales",
        "CRMs, prospecting, sales engagement and LinkedIn are Work.",
        kind: .work, idPrefix: "47000000", defaultFor: [.sales], [
            site(1, "Salesforce", "salesforce.com"),
            site(2, "Salesforce Lightning", "force.com"),
            site(3, "HubSpot", "hubspot.com"),
            site(4, "LinkedIn", "linkedin.com"),
            site(5, "Pipedrive", "pipedrive.com"),
            site(6, "Outreach", "outreach.io"),
            site(7, "Salesloft", "salesloft.com"),
            site(8, "Apollo", "apollo.io"),
            site(9, "Gong", "gong.io"),
            site(10, "ZoomInfo", "zoominfo.com"),
            site(11, "Close", "close.com"),
            site(12, "Copper", "copper.com"),
            site(13, "Freshworks", "myfreshworks.com"),
            host(14, "Zoho CRM", "crm.zoho.com"),
            host(15, "Zoho CRM EU", "crm.zoho.eu"),
            site(16, "PandaDoc", "pandadoc.com"),
            site(17, "Lusha", "lusha.com"),
            site(18, "Seamless.AI", "seamless.ai"),
            site(19, "Clari", "clari.com"),
            site(20, "Highspot", "highspot.com"),
            site(21, "Seismic", "seismic.com"),
            site(22, "Attio", "attio.com"),
            site(23, "lemlist", "lemlist.com"),
            site(24, "Instantly", "instantly.ai")
        ])

    static let businessOwner = pack(
        "business-owner", "Running a business",
        "Store admin, payments, accounting, payroll and hiring dashboards are Work.",
        kind: .work, idPrefix: "48000000", defaultFor: [.businessOwner], [
            host(1, "Shopify admin", "admin.shopify.com"),
            host(2, "Stripe Dashboard", "dashboard.stripe.com"),
            host(3, "QuickBooks Online", "qbo.intuit.com"),
            host(4, "QuickBooks", "quickbooks.intuit.com"),
            site(5, "Xero", "xero.com"),
            site(6, "FreshBooks", "freshbooks.com"),
            site(7, "Wave", "waveapps.com"),
            site(8, "Square", "squareup.com"),
            site(9, "Toast", "toasttab.com"),
            site(10, "Gusto", "gusto.com"),
            site(11, "Rippling", "rippling.com"),
            host(12, "Amazon Seller Central", "sellercentral.amazon.com"),
            host(13, "Amazon Seller Central Europe", "sellercentral-europe.amazon.com"),
            site(14, "BILL", "bill.com"),
            site(15, "Expensify", "expensify.com"),
            host(16, "Mercury", "app.mercury.com"),
            host(17, "Brex", "dashboard.brex.com"),
            host(18, "Ramp", "app.ramp.com"),
            host(19, "Wix dashboard", "manage.wix.com"),
            site(20, "Squarespace", "squarespace.com"),
            host(21, "Indeed for Employers", "employers.indeed.com"),
            site(22, "Upwork", "upwork.com"),
            site(23, "Fiverr", "fiverr.com")
        ])

    static let writing = pack(
        "writing", "Writing and editing",
        "Manuscript editors, word processors, style guides and publishing dashboards are Work.",
        kind: .work, idPrefix: "49000000", defaultFor: [.writer], [
            app(1, "Scrivener", "com.literatureandlatte.scrivener3"),
            app(2, "Ulysses", "com.ulyssesapp.mac"),
            app(3, "iA Writer", "pro.writer.mac"),
            app(4, "Microsoft Word", "com.microsoft.Word"),
            app(5, "Pages", "com.apple.iWork.Pages"),
            site(6, "Grammarly", "grammarly.com"),
            site(7, "Hemingway Editor", "hemingwayapp.com"),
            site(8, "ProWritingAid", "prowritingaid.com"),
            site(9, "QuillBot", "quillbot.com"),
            site(10, "Merriam-Webster", "merriam-webster.com"),
            site(11, "Thesaurus.com", "thesaurus.com"),
            site(12, "Chicago Manual of Style", "chicagomanualofstyle.org"),
            site(13, "AP Stylebook", "apstylebook.com"),
            site(14, "WordPress.com", "wordpress.com"),
            site(15, "Ghost", "ghost.io"),
            site(16, "Reedsy", "reedsy.com"),
            site(17, "Submittable", "submittable.com"),
            site(18, "Duotrope", "duotrope.com")
        ])

    static let education = pack(
        "education", "Teaching",
        "Learning management systems, grading and classroom tools are Work.",
        kind: .work, idPrefix: "4A000000", defaultFor: [.educator], [
            site(1, "Canvas", "instructure.com"),
            site(2, "Blackboard", "blackboard.com"),
            host(3, "Google Classroom", "classroom.google.com"),
            site(4, "Schoology", "schoology.com"),
            site(5, "Brightspace", "brightspace.com"),
            site(6, "Moodle Cloud", "moodlecloud.com"),
            site(7, "PowerSchool", "powerschool.com"),
            site(8, "Gradescope", "gradescope.com"),
            site(9, "Turnitin", "turnitin.com"),
            site(10, "Kahoot!", "kahoot.it"),
            site(11, "Kahoot!", "kahoot.com"),
            site(12, "Quizizz", "quizizz.com"),
            site(13, "Blooket", "blooket.com"),
            site(14, "Nearpod", "nearpod.com"),
            site(15, "Edpuzzle", "edpuzzle.com"),
            site(16, "Padlet", "padlet.com"),
            site(17, "Seesaw", "seesaw.me"),
            site(18, "ClassDojo", "classdojo.com"),
            site(19, "Teachers Pay Teachers", "teacherspayteachers.com"),
            site(20, "Desmos", "desmos.com"),
            site(21, "Remind", "remind.com"),
            site(22, "Pear Deck", "peardeck.com"),
            site(23, "Formative", "goformative.com")
        ])

    static let research = pack(
        "research", "Research",
        "Reference managers, journals, preprint servers and literature databases are Work.",
        kind: .work, idPrefix: "4B000000", defaultFor: [.researcher], [
            app(1, "Zotero", "org.zotero.zotero"),
            app(2, "RStudio", "com.rstudio.desktop"),
            host(3, "Google Scholar", "scholar.google.com"),
            site(4, "PubMed and NCBI", "ncbi.nlm.nih.gov"),
            site(5, "arXiv", "arxiv.org"),
            site(6, "bioRxiv", "biorxiv.org"),
            site(7, "medRxiv", "medrxiv.org"),
            site(8, "SSRN", "ssrn.com"),
            site(9, "JSTOR", "jstor.org"),
            site(10, "ScienceDirect", "sciencedirect.com"),
            site(11, "Springer", "springer.com"),
            site(12, "Nature", "nature.com"),
            site(13, "Wiley Online Library", "wiley.com"),
            site(14, "Taylor & Francis", "tandfonline.com"),
            site(15, "PLOS", "plos.org"),
            site(16, "Frontiers", "frontiersin.org"),
            site(17, "MDPI", "mdpi.com"),
            host(18, "IEEE Xplore", "ieeexplore.ieee.org"),
            host(19, "ACM Digital Library", "dl.acm.org"),
            site(20, "ResearchGate", "researchgate.net"),
            site(21, "Semantic Scholar", "semanticscholar.org"),
            site(22, "Connected Papers", "connectedpapers.com"),
            site(23, "Elicit", "elicit.com"),
            site(24, "Web of Science", "webofscience.com"),
            site(25, "Scopus", "scopus.com"),
            site(26, "ORCID", "orcid.org"),
            site(27, "DOI", "doi.org"),
            site(28, "Overleaf", "overleaf.com"),
            site(29, "Zotero on the web", "zotero.org"),
            site(30, "Mendeley", "mendeley.com"),
            site(31, "OSF", "osf.io"),
            site(32, "protocols.io", "protocols.io"),
            site(33, "ClinicalTrials.gov", "clinicaltrials.gov"),
            site(34, "Qualtrics", "qualtrics.com"),
            site(35, "Prolific", "prolific.com")
        ])

    static let healthcare = pack(
        "healthcare", "Healthcare",
        "Clinical references, medical journals, practice management and telehealth tools are Work.",
        kind: .work, idPrefix: "4C000000", defaultFor: [.healthcare], [
            site(1, "UpToDate", "uptodate.com"),
            site(2, "Medscape", "medscape.com"),
            site(3, "PubMed and NCBI", "ncbi.nlm.nih.gov"),
            site(4, "DynaMed", "dynamed.com"),
            site(5, "ClinicalKey", "clinicalkey.com"),
            site(6, "Epocrates", "epocrates.com"),
            host(7, "Lexicomp", "online.lexi.com"),
            site(8, "Micromedex", "micromedexsolutions.com"),
            site(9, "VisualDx", "visualdx.com"),
            site(10, "MDCalc", "mdcalc.com"),
            site(11, "OpenEvidence", "openevidence.com"),
            site(12, "AMBOSS", "amboss.com"),
            site(13, "Merck Manuals", "merckmanuals.com"),
            site(14, "NEJM", "nejm.org"),
            site(15, "JAMA Network", "jamanetwork.com"),
            site(16, "The Lancet", "thelancet.com"),
            site(17, "The BMJ", "bmj.com"),
            site(18, "ClinicalTrials.gov", "clinicaltrials.gov"),
            site(19, "Doximity", "doximity.com"),
            site(20, "athenahealth", "athenahealth.com"),
            site(21, "DrChrono", "drchrono.com"),
            site(22, "Tebra", "tebra.com"),
            site(23, "SimplePractice", "simplepractice.com"),
            site(24, "TherapyNotes", "therapynotes.com"),
            site(25, "Jane", "jane.app"),
            site(26, "Doxy.me", "doxy.me")
        ])

    static let legal = pack(
        "legal", "Legal",
        "Legal research, practice management, e-discovery, court filings and Word are Work.",
        kind: .work, idPrefix: "4D000000", defaultFor: [.legal], [
            app(1, "Microsoft Word", "com.microsoft.Word"),
            site(2, "Westlaw", "westlaw.com"),
            site(3, "Lexis", "lexis.com"),
            site(4, "LexisNexis", "lexisnexis.com"),
            site(5, "Bloomberg Law", "bloomberglaw.com"),
            site(6, "vLex", "vlex.com"),
            site(7, "Casetext", "casetext.com"),
            site(8, "Harvey", "harvey.ai"),
            site(9, "Clio", "clio.com"),
            site(10, "MyCase", "mycase.com"),
            site(11, "PracticePanther", "practicepanther.com"),
            site(12, "NetDocuments", "netdocuments.com"),
            site(13, "iManage", "cloudimanage.com"),
            site(14, "RelativityOne", "relativity.one"),
            site(15, "Everlaw", "everlaw.com"),
            site(16, "Ironclad", "ironcladapp.com"),
            site(17, "DocuSign", "docusign.com"),
            site(18, "DocuSign signing", "docusign.net"),
            site(19, "PACER and US Courts", "uscourts.gov"),
            site(20, "CourtListener", "courtlistener.com"),
            host(21, "Justia Law", "law.justia.com"),
            site(22, "SEC", "sec.gov"),
            site(23, "Law360", "law360.com")
        ])

    static let finance = pack(
        "finance", "Finance and accounting",
        "Spreadsheets, accounting, ERP, market data, filings and financial news are Work.",
        kind: .work, idPrefix: "4E000000", defaultFor: [.finance], [
            app(1, "Excel", "com.microsoft.Excel"),
            host(2, "QuickBooks Online", "qbo.intuit.com"),
            host(3, "QuickBooks", "quickbooks.intuit.com"),
            host(4, "Intuit ProConnect", "proconnect.intuit.com"),
            site(5, "Xero", "xero.com"),
            site(6, "NetSuite", "netsuite.com"),
            site(7, "BILL", "bill.com"),
            site(8, "Expensify", "expensify.com"),
            site(9, "SAP Concur", "concursolutions.com"),
            site(10, "Anaplan", "anaplan.com"),
            site(11, "Workiva", "workiva.com"),
            site(12, "FloQast", "floqast.com"),
            site(13, "BlackLine", "blackline.com"),
            site(14, "Carta", "carta.com"),
            site(15, "FactSet", "factset.com"),
            site(16, "S&P Capital IQ", "capitaliq.com"),
            host(17, "S&P Capital IQ Pro", "capitaliq.spglobal.com"),
            site(18, "PitchBook", "pitchbook.com"),
            host(19, "LSEG Workspace", "workspace.refinitiv.com"),
            site(20, "SEC", "sec.gov"),
            site(21, "Bloomberg", "bloomberg.com"),
            site(22, "The Wall Street Journal", "wsj.com"),
            site(23, "Financial Times", "ft.com")
        ])

    static let engineering = pack(
        "engineering", "Engineering",
        "CAD, simulation, electronics design and parts suppliers are Work.",
        kind: .work, idPrefix: "4F000000", defaultFor: [.engineer], [
            app(1, "MATLAB", "com.mathworks.matlab"),
            app(2, "Mathematica", "com.wolfram.Mathematica"),
            app(3, "Fusion", "com.autodesk.fusion360"),
            app(4, "KiCad", "org.kicad.kicad"),
            app(5, "FreeCAD", "org.freecad.FreeCAD"),
            app(6, "OpenSCAD", "org.openscad.OpenSCAD"),
            app(7, "Arduino IDE", "cc.arduino.IDE2"),
            host(8, "Onshape", "cad.onshape.com"),
            host(9, "IEEE Xplore", "ieeexplore.ieee.org"),
            site(10, "Wolfram|Alpha", "wolframalpha.com"),
            site(11, "DigiKey", "digikey.com"),
            site(12, "Mouser", "mouser.com"),
            site(13, "Octopart", "octopart.com"),
            site(14, "McMaster-Carr", "mcmaster.com"),
            site(15, "GrabCAD", "grabcad.com"),
            site(16, "The Engineering ToolBox", "engineeringtoolbox.com"),
            site(17, "MatWeb", "matweb.com"),
            site(18, "EasyEDA", "easyeda.com"),
            site(19, "JLCPCB", "jlcpcb.com"),
            site(20, "Altium 365", "altium365.com")
        ])

    static let skilledTrades = pack(
        "skilled-trades", "Skilled trades",
        "Field service, job management, building codes and trade suppliers are Work.",
        kind: .work, idPrefix: "50000000", defaultFor: [.skilledTrades], [
            site(1, "Jobber", "getjobber.com"),
            site(2, "ServiceTitan", "servicetitan.com"),
            site(3, "Housecall Pro", "housecallpro.com"),
            site(4, "Buildertrend", "buildertrend.net"),
            site(5, "Procore", "procore.com"),
            site(6, "CompanyCam", "companycam.com"),
            site(7, "Fieldwire", "fieldwire.com"),
            site(8, "JobNimbus", "jobnimbus.com"),
            site(9, "ServiceM8", "servicem8.com"),
            site(10, "Tradify", "tradifyhq.com"),
            host(11, "Autodesk Construction Cloud", "acc.autodesk.com"),
            host(12, "SketchUp for Web", "app.sketchup.com"),
            host(13, "ICC Codes", "codes.iccsafe.org"),
            site(14, "UpCodes", "up.codes"),
            host(15, "Angi for Pros", "pro.angi.com"),
            site(16, "Ferguson", "ferguson.com"),
            site(17, "Grainger", "grainger.com"),
            site(18, "Fastenal", "fastenal.com")
        ])

    static let operations = pack(
        "operations", "Operations",
        "Ticketing, procurement, logistics, scheduling and workflow tools are Work.",
        kind: .work, idPrefix: "51000000", defaultFor: [.operations], [
            site(1, "Asana", "asana.com"),
            site(2, "monday.com", "monday.com"),
            site(3, "Smartsheet", "smartsheet.com"),
            site(4, "Jira and Confluence", "atlassian.net"),
            site(5, "ServiceNow", "service-now.com"),
            site(6, "Zendesk", "zendesk.com"),
            site(7, "Freshdesk", "freshdesk.com"),
            host(8, "Intercom", "app.intercom.com"),
            site(9, "Front", "frontapp.com"),
            site(10, "NetSuite", "netsuite.com"),
            site(11, "Coupa", "coupahost.com"),
            site(12, "SAP Ariba", "ariba.com"),
            site(13, "ShipStation", "shipstation.com"),
            site(14, "Flexport", "flexport.com"),
            site(15, "Samsara", "samsara.com"),
            site(16, "Workday", "myworkday.com"),
            host(17, "ADP Workforce Now", "workforcenow.adp.com"),
            site(18, "Deputy", "deputy.com"),
            site(19, "When I Work", "wheniwork.com"),
            site(20, "Homebase", "joinhomebase.com"),
            site(21, "Lucid", "lucid.app"),
            site(22, "Zapier", "zapier.com")
        ])

    static let student = pack(
        "student", "Studying",
        "Course sites, homework platforms, study tools and academic databases count as Work.",
        kind: .work, idPrefix: "52000000", defaultFor: [.student], [
            site(1, "Canvas", "instructure.com"),
            site(2, "Blackboard", "blackboard.com"),
            host(3, "Google Classroom", "classroom.google.com"),
            site(4, "Schoology", "schoology.com"),
            site(5, "Brightspace", "brightspace.com"),
            site(6, "Gradescope", "gradescope.com"),
            site(7, "Turnitin", "turnitin.com"),
            site(8, "Piazza", "piazza.com"),
            site(9, "Ed Discussion", "edstem.org"),
            site(10, "Perusall", "perusall.com"),
            site(11, "Top Hat", "tophat.com"),
            host(12, "McGraw Hill Connect", "connect.mheducation.com"),
            site(13, "Quizlet", "quizlet.com"),
            site(14, "Chegg", "chegg.com"),
            site(15, "Course Hero", "coursehero.com"),
            site(16, "Studocu", "studocu.com"),
            site(17, "Khan Academy", "khanacademy.org"),
            site(18, "Coursera", "coursera.org"),
            site(19, "edX", "edx.org"),
            site(20, "Desmos", "desmos.com"),
            site(21, "Wolfram|Alpha", "wolframalpha.com"),
            site(22, "Symbolab", "symbolab.com"),
            site(23, "Overleaf", "overleaf.com"),
            site(24, "JSTOR", "jstor.org"),
            host(25, "Google Scholar", "scholar.google.com"),
            app(26, "Zotero", "org.zotero.zotero"),
            app(27, "Anki", "net.ankiweb.dtop")
        ])

    private struct Entry {
        var number: Int
        var name: String
        var condition: RuleCondition
    }

    private static func app(_ number: Int, _ name: String, _ bundleIdentifier: String) -> Entry {
        Entry(number: number, name: name, condition: RuleCondition(field: .bundleIdentifier, operation: .equals, value: bundleIdentifier))
    }

    private static func site(_ number: Int, _ name: String, _ domain: String) -> Entry {
        Entry(number: number, name: name, condition: RuleCondition(field: .host, operation: .domain, value: domain))
    }

    private static func host(_ number: Int, _ name: String, _ host: String) -> Entry {
        Entry(number: number, name: name, condition: RuleCondition(field: .host, operation: .equals, value: host))
    }

    private static func pack(
        _ id: String, _ name: String, _ summary: String, kind: ActivityKind, idPrefix: String,
        defaultFor professions: Set<ReviewAIProfession>, _ entries: [Entry]
    ) -> StarterPreset {
        let categoryID = kind == .personal ? SeedData.personalCategoryID : SeedData.workCategoryID
        let rules = entries.map { entry in
            let number = String(entry.number)
            let uuid = "\(idPrefix)-0000-0000-0000-\(String(repeating: "0", count: max(0, 12 - number.count)))\(number)"
            return Rule(id: UUID(uuidString: uuid)!, name: "\(entry.name) is \(kind.displayName)", priority: 500, enabled: true, isBuiltIn: true,
                        action: RuleAction(kind: kind, categoryID: categoryID, projectID: nil),
                        conditions: [entry.condition], origin: .preset, presetID: id)
        }
        return StarterPreset(id: id, name: name, summary: summary, defaultProfessions: professions, rules: rules)
    }
}

public struct RuleMatchSummary: Equatable, Sendable {
    public var count: Int
    public var seconds: TimeInterval
}

public struct RecordedApp: Identifiable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var seconds: TimeInterval

    public var id: String { bundleIdentifier }
}

public struct RuleImpactPreview: Sendable {
    public var affectedCount: Int
    public var affectedSeconds: TimeInterval
    public var examples: [String]
}

public struct CorrectionLearningSuggestion: Identifiable, Sendable {
    public var id: String
    public var rule: Rule
    public var days: Int
    public var evidenceKey: String
}
