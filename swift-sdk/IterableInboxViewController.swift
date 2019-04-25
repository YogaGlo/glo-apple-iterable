//
//  Created by Tapash Majumder on 4/11/19.
//  Copyright © 2019 Iterable. All rights reserved.
//

import UIKit

open class IterableInboxViewController: UITableViewController {
    /// If you want to use a custom layout for your Inbox TableViewCell
    /// this is where you should override it. Please note that this assumes
    /// that the xib is present in the main bundle.
    @IBInspectable public var cellNibName: String? = nil
    
    // MARK: Initializers
    public override init(style: UITableView.Style) {
        ITBInfo()
        super.init(style: style)
     
        IterableInboxViewController.setup(instance: self)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        ITBInfo()
        super.init(coder: aDecoder)
        
        IterableInboxViewController.setup(instance: self)
    }
    
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        ITBInfo()
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        IterableInboxViewController.setup(instance: self)
    }
    
    override open func viewDidLoad() {
        ITBInfo()
        super.viewDidLoad()

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 150
        
        registerTableViewCell()
    }

    // MARK: - Table view data source
    override open func numberOfSections(in tableView: UITableView) -> Int {
        return diffCalculator?.numberOfSections() ?? 0
    }

    override open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return diffCalculator?.numberOfObjects(inSection: section) ?? 0
    }

    override open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "inboxCell", for: indexPath) as? IterableInboxCell else {
            fatalError("Please make sure that an the nib: \(cellNibName!) is present in the main bundle")
        }

        if let viewModel = diffCalculator?.value(atIndexPath: indexPath) {
            configure(cell: cell, forViewModel: viewModel)
        }

        return cell
    }

    // Override to support conditional editing of the table view.
    override open func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    // Override to support editing the table view.
    override open func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            guard let iterableMessage = diffCalculator?.value(atIndexPath: indexPath).iterableMessage else {
                return
            }
            IterableAPI.inAppManager.remove(message: iterableMessage)
        }
    }
    
    override open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let iterableMessage = diffCalculator?.value(atIndexPath: indexPath).iterableMessage else {
            return
        }
        if let viewController = IterableAPI.inAppManager.createInboxMessageViewController(for: iterableMessage) {
            IterableAPI.inAppManager.set(read: true, forMessage: iterableMessage)
            viewController.navigationItem.title = iterableMessage.inboxMetadata?.title
            navigationController?.pushViewController(viewController, animated: true)
        }
    }

    private let iterableCellNibName = "IterableInboxCell"
    
    private lazy var diffCalculator: TableViewDiffCalculator<Int, InboxMessageViewModel>? = {
        TableViewDiffCalculator(tableView: self.tableView, initialSectionedValues: SectionedValues([]))
    }()
    
    private static func setup(instance: IterableInboxViewController) {
        instance.refreshMessages()
        NotificationCenter.default.addObserver(instance, selector: #selector(onInboxChanged(notification:)), name: .iterableInboxChanged, object: nil)
    }
    
    deinit {
        ITBInfo()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func registerTableViewCell() {
        let cellNibName = self.cellNibName ?? self.iterableCellNibName
        let bundle = self.cellNibName == nil ? Bundle(for: IterableInboxViewController.self) : Bundle.main
        
        let nib = UINib(nibName: cellNibName, bundle: bundle)
        tableView.register(nib, forCellReuseIdentifier: "inboxCell")
    }
    
    @objc private func onInboxChanged(notification: NSNotification) {
        ITBInfo()
        refreshMessages()
    }
    
    private func refreshMessages() {
        ITBInfo()
        DispatchQueue.main.async { [weak self] in
            self?.updateUnreadBadgeCount()
            self?.diffCalculator?.sectionedValues = IterableInboxViewController.createSectionedValues(fromInboxMessages: IterableAPI.inAppManager.getInboxMessages())
        }
    }
    
    private func updateUnreadBadgeCount() {
        let unreadCount = IterableAPI.inAppManager.getUnreadInboxMessagesCount()
        let badgeValue = unreadCount == 0 ? nil : "\(unreadCount)"
        navigationController?.tabBarItem?.badgeValue = badgeValue
    }
    
    private static func createSectionedValues(fromInboxMessages inboxMessages: [IterableInAppMessage]) -> SectionedValues<Int, InboxMessageViewModel> {
        let viewModels = inboxMessages.map { InboxMessageViewModel.from(message: $0) }
        return SectionedValues([(0, viewModels)])
    }
    
    private func configure(cell: IterableInboxCell, forViewModel viewModel: InboxMessageViewModel) {
        cell.titleLbl?.text = viewModel.title
        cell.subTitleLbl?.text = viewModel.subTitle
        cell.unreadCircleView?.isHidden = viewModel.read
        
        cell.iconImageView?.layer.cornerRadius = 5
        cell.iconImageView?.clipsToBounds = true

        if let imageUrlString = viewModel.imageUrl, let url = URL(string: imageUrlString) {
            cell.iconContainerView?.isHidden = false
            cell.iconImageView?.isHidden = false

            if let data = viewModel.imageData {
                cell.iconImageView?.backgroundColor = nil
                cell.iconImageView?.image = UIImage(data: data)
            } else {
                cell.iconImageView?.backgroundColor = UIColor(hex: "EEEEEE") // loading image
                cell.iconImageView?.image = nil
                loadImage(forMessageId: viewModel.iterableMessage.messageId, fromUrl: url)
            }
        } else {
            cell.iconContainerView?.isHidden = true
            cell.iconImageView?.isHidden = true
        }
        
        cell.timeLbl?.isHidden = true
    }

    private func loadImage(forMessageId messageId: String, fromUrl url: URL) {
        if let networkSession = IterableAPI.internalImplementation?.networkSession {
            NetworkHelper.getData(fromUrl: url, usingSession: networkSession).onSuccess {[weak self] in
                self?.updateCell(forMessageId: messageId, withData: $0)
            }.onError {
                ITBError($0.localizedDescription)
            }
        }
    }
    
    private func updateCell(forMessageId messageId: String, withData data: Data) {
        guard var viewModels = diffCalculator?.sectionedValues[0].1 else {
            return
        }
        
        guard let row = viewModels.firstIndex (where: { $0.iterableMessage.messageId == messageId }) else {
            return
        }
        var viewModel = viewModels[row]
        viewModel.imageData = data
        viewModels[row] = viewModel
        
        diffCalculator?._sectionedValues = SectionedValues([(0, viewModels)])

        tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .automatic)
    }
}
